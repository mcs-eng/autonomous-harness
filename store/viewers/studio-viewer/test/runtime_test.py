"""Workspace safety and success/failure contracts for every copied runner."""
import contextlib
import errno
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

STORE = Path(__file__).resolve().parents[3]
coverage = None
if os.environ.get('STUDIO_COVERAGE'):
    from coverage import Coverage
    coverage = Coverage(branch=True, data_file=None, include=[str(STORE/'tools/studio_runtime.py')])
    coverage.start()
sys.path.insert(0, str(STORE/'tools'))
import studio_runtime as runtime

CONFIG = {'title':'Test studio', 'controls':[
    {'id':'steps','label':'Steps','type':'number','value':2,'min':1,'max':5,'integer':True},
    {'id':'shape','label':'Shape','type':'select','value':'round','options':[{'value':'round'},{'value':'square'}]},
    {'id':'text','label':'Text','type':'text','value':'hello','maxLength':8}], 'actions':[{'id':'make'}]}

class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='studio-runtime-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.workspace = self.root/'workspace'; self.workspace.mkdir()
        self.package = self.root/'package'; self.package.mkdir()
        (self.package/'studio.config.json').write_text(json.dumps(CONFIG))
        (self.package/'upstream.lock.json').write_text('[]')
        (self.workspace/'studio.json').write_text(json.dumps({'parameters':{}}))
        self.enterContext(patch.dict(os.environ, HARNESS_WORKSPACE=str(self.workspace)))
        self.enterContext(patch.object(runtime,'__file__',str(self.package/'toolchain/studio_runtime.py')))
        self.enterContext(patch.object(sys,'argv',['run']))

    def call(self, action=None):
        code, _, _ = self.invoke(action)
        if code:
            raise SystemExit(code)

    def invoke(self, action=None):
        def make(p, out):
            (out/'hello.txt').write_text('A real artifact')
            return {'title':'Done', 'engine':'Test', 'metrics':[runtime.metric('Count',2)],
                    'files':[{'label':'Text','name':'hello.txt'}]}
        stdout=io.StringIO();stderr=io.StringIO()
        try:
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                runtime.execute({'make':action or make})
        except SystemExit as exc:
            return exc.code,stdout.getvalue(),stderr.getvalue()
        return 0,stdout.getvalue(),stderr.getvalue()

    def assert_write_failure(self, error, matches):
        self.call()
        latest=self.workspace/'out/latest.json';before=latest.read_bytes()
        prior=json.loads(before)['id'];real=runtime.atomic_json;raised=[]
        def fail_once(path,data):
            if not raised and matches(Path(path),data):
                raised.append(Path(path));raise error
            return real(path,data)
        with patch.object(runtime,'atomic_json',side_effect=fail_once):
            code,stdout,stderr=self.invoke()
        self.assertEqual(len(raised),1)
        self.assertEqual(code,1)
        self.assertEqual(stderr,f'Studio run failed: {error.strerror}\n')
        self.assertNotIn('Ready:',stdout)
        self.assertEqual(latest.read_bytes(),before)
        self.assertEqual([row['id'] for row in runtime.previous_runs()],[prior])
        self.assertFalse(json.loads((self.workspace/'.harness/verdict.json').read_text())['ready'])

    def test_successful_runs_are_immutable_and_failed_runs_preserve_latest(self):
        self.call()
        first=(self.workspace/'out/latest.json').read_bytes()
        result=json.loads(first)
        self.assertTrue((self.workspace/result['artifacts'][0]['path']).is_file())
        self.assertEqual(result['parameters'],{'steps':2,'shape':'round','text':'hello'})
        self.assertTrue(json.loads((self.workspace/'.harness/verdict.json').read_text())['ready'])
        def fail(p,out): raise RuntimeError('Please choose another idea')
        with self.assertRaises(SystemExit): self.call(fail)
        self.assertEqual((self.workspace/'out/latest.json').read_bytes(), first)
        verdict=json.loads((self.workspace/'.harness/verdict.json').read_text())
        self.assertFalse(verdict['ready']); self.assertIn('choose another',verdict['summary'])
        self.call()
        self.assertEqual(len(runtime.previous_runs()),2)
        broken=self.workspace/'out/runs/broken'; broken.mkdir(); (broken/'result.json').write_text('partial')
        (self.root/'secret').write_text('{}')
        outside=self.workspace/'out/runs/outside'; outside.mkdir(); (outside/'result.json').symlink_to(self.root/'secret')
        self.assertEqual(len(runtime.previous_runs()),2)

    def test_input_failures_produce_actionable_verdicts(self):
        for argv,content in [(['run','unknown'],'{}'), (['run'],'x'*16385), (['run'],'broken'),
                             (['run'],'{}'), (['run'],'{"parameters":{"steps":false}}')]:
            with self.subTest(argv=argv,content=content[:30]):
                (self.workspace/'studio.json').write_text(content)
                with patch.object(sys,'argv',argv), self.assertRaises(SystemExit): self.call()
                self.assertFalse(json.loads((self.workspace/'.harness/verdict.json').read_text())['ready'])
        (self.workspace/'studio.json').unlink()
        with self.assertRaises(SystemExit): self.call()

    def test_rejects_missing_empty_and_escaping_artifacts(self):
        for name in ['missing.txt','../outside.txt','../../../outside.txt']:
            with self.subTest(name=name), self.assertRaises(SystemExit):
                self.call(lambda p,out: {'files':[{'label':'Output','name':name}]})
        def empty(p,out):
            (out/'empty').touch()
            return {'files':[{'label':'Empty','name':'empty'}]}
        with self.assertRaises(SystemExit): self.call(empty)
        self.assertFalse((self.workspace/'out/latest.json').exists())

    def test_confinement_and_atomic_writes(self):
        target=self.workspace/'state.json'
        with patch.object(runtime.tempfile,'NamedTemporaryFile',wraps=runtime.tempfile.NamedTemporaryFile) as temporary:
            runtime.atomic_json(target,{'value':1})
        self.assertEqual(temporary.call_args.kwargs['mode'],'wb')
        self.assertFalse(temporary.call_args.kwargs['delete'])
        with self.assertRaises(ValueError): runtime.atomic_json(target,{'value':math.nan})
        self.assertEqual(json.loads(target.read_text()),{'value':1})
        self.assertEqual(list(self.workspace.glob('.studio-*')),[])
        with patch.object(runtime.os,'fsync',side_effect=OSError(errno.ENOSPC,'No space left on device')), \
             self.assertRaises(OSError):
            runtime.atomic_json(target,{'value':2})
        self.assertEqual(json.loads(target.read_text()),{'value':1})
        self.assertEqual(list(self.workspace.glob('.studio-*')),[])
        with patch.object(runtime.tempfile,'NamedTemporaryFile',side_effect=PermissionError(errno.EACCES,'Permission denied')), \
             self.assertRaises(PermissionError):
            runtime.atomic_json(target,{'value':2})
        self.assertEqual(json.loads(target.read_text()),{'value':1})
        with self.assertRaises(ValueError): runtime.contained(self.root/'secret')
        (self.workspace/'escape').symlink_to(self.root,target_is_directory=True)
        with self.assertRaises(ValueError): runtime.atomic_json(self.workspace/'escape/secret',{})
        (self.workspace/'.harness').symlink_to(self.root,target_is_directory=True)
        with self.assertRaises(SystemExit): self.call()
        self.assertFalse((self.root/'verdict.json').exists())

    def test_publication_records_fail_closed(self):
        run=self.workspace/'out/runs/one';run.mkdir(parents=True)
        result_path=run/'result.json';token='a'*32
        publication={'spec':1,'token':token};result={'id':'one','publication':publication}
        self.assertTrue(runtime._published(result_path,{'id':'one'},{}))
        for malformed in [[], {'id':'one','publication':None},
                          {'id':'one','publication':{'spec':2,'token':token}},
                          {'id':'one','publication':{'spec':1,'token':1}},
                          {'id':'one','publication':{'spec':1,'token':'a'}},
                          {'id':'one','publication':{'spec':1,'token':'z'*32}},
                          {'id':'other','publication':publication}]:
            with self.subTest(malformed=malformed):
                self.assertFalse(runtime._published(result_path,malformed,{}))
        self.assertFalse(runtime._published(result_path,result,{}))
        (run/'.published.json').write_text(json.dumps({'spec':1,'id':'one','token':'b'*32}))
        self.assertFalse(runtime._published(result_path,result,{}))
        (run/'.published.json').write_text(json.dumps({'spec':1,'id':'one','token':token}))
        self.assertTrue(runtime._published(result_path,result,{}))
        verdict={'ready':True,'runId':'one','publication':publication,'artifact':'out/runs/one/result.json'}
        (run/'.published.json').unlink()
        self.assertTrue(runtime._published(result_path,result,verdict))
        verdict_path=self.workspace/'.harness/verdict.json';verdict_path.parent.mkdir()
        verdict_path.write_text('[]');self.assertEqual(runtime._current_verdict(),{})
        verdict_path.write_text('broken');self.assertEqual(runtime._current_verdict(),{})

    def test_invalid_current_publications_are_not_archived(self):
        verdict_path=self.workspace/'.harness/verdict.json';verdict_path.parent.mkdir()
        publication={'spec':1,'token':'a'*32}
        verdict_path.write_text('[]')
        with self.assertRaisesRegex(ValueError,'invalid publication'):
            runtime._archive_current_result()
        verdict_path.write_text(json.dumps({'ready':True,'publication':publication}))
        with self.assertRaisesRegex(ValueError,'invalid publication'):
            runtime._archive_current_result()
        verdict_path.write_text(json.dumps({'ready':True,'runId':'missing','publication':publication,
                                            'artifact':'out/runs/missing/result.json'}))
        with self.assertRaisesRegex(ValueError,'cannot be finalized'):
            runtime._archive_current_result()
        other=self.workspace/'out/runs/other';other.mkdir(parents=True)
        (other/'result.json').write_text(json.dumps({'id':'other','publication':publication}))
        verdict_path.write_text(json.dumps({'ready':True,'runId':'wanted','publication':publication,
                                            'artifact':'out/runs/other/result.json'}))
        with self.assertRaisesRegex(ValueError,'invalid publication'):
            runtime._archive_current_result()

    def test_unreadable_current_verdict_stops_before_replacing_it(self):
        self.call();verdict_path=self.workspace/'.harness/verdict.json';before=verdict_path.read_bytes()
        prior=json.loads(before)['runId'];real=runtime._read_json
        def unreadable(path):
            if Path(path).resolve()==verdict_path.resolve():
                raise PermissionError(errno.EACCES,'Permission denied')
            return real(path)
        with patch.object(runtime,'_read_json',side_effect=unreadable):
            code,stdout,stderr=self.invoke()
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,'Studio run failed: Permission denied\n')
        self.assertEqual(verdict_path.read_bytes(),before)
        self.assertEqual([row['id'] for row in runtime.previous_runs()],[prior])

    def test_conflicting_archived_publication_stops_the_next_run(self):
        self.call();verdict=json.loads((self.workspace/'.harness/verdict.json').read_text())
        result=self.workspace/verdict['artifact'];marker=result.parent/'.published.json'
        runtime._archive_current_result();runtime._archive_current_result()
        marker.write_text(json.dumps({'spec':1,'id':verdict['runId'],'token':'f'*32}))
        code,stdout,stderr=self.invoke()
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,'Studio run failed: The current studio result has invalid publication state\n')
        self.assertTrue(json.loads((self.workspace/'.harness/verdict.json').read_text())['ready'])

    def test_control_types_and_boundaries(self):
        self.assertEqual(runtime.parameters(CONFIG,{'steps':1})['steps'],1)
        self.assertEqual(runtime.parameters(CONFIG,{'steps':5})['steps'],5)
        for value in [[],None,{'extra':1},{'steps':True},{'steps':None},{'steps':'2'},
                      {'steps':math.inf},{'steps':0},{'steps':2.5},{'shape':'other'},{'text':1},{'text':'a'*9}]:
            with self.subTest(value=value), self.assertRaises(ValueError): runtime.parameters(CONFIG,value)
        self.assertEqual(runtime.metric('X',1,'m'),{'label':'X','value':1,'unit':'m'})

    def test_commands_capture_logs_and_bound_runtime(self):
        self.assertEqual(runtime.command([sys.executable,'-c','print("hello")']).strip(),'hello')
        for code in ['import sys;print("helpful",file=sys.stderr);sys.exit(2)','import sys;print("output");sys.exit(2)','raise SystemExit(3)']:
            with self.assertRaises(RuntimeError): runtime.command([sys.executable,'-c',code])
        with self.assertRaises(subprocess.TimeoutExpired):
            runtime.command([sys.executable,'-c','import time;time.sleep(10)'],timeout=.05)

    def test_lock_backends_and_contention(self):
        class Handle:
            def __init__(self):self.positions=[]
            def seek(self,position,*args):self.positions.append((position,args))
            def fileno(self):return 7
        class Backend:
            LK_NBLCK=1;LK_UNLCK=2;LOCK_EX=4;LOCK_NB=8;LOCK_UN=16
            def __init__(self):self.calls=[]
            def locking(self,*args):self.calls.append(('locking',args))
            def flock(self,*args):self.calls.append(('flock',args))
        handle=Handle();backend=Backend()
        runtime._file_lock(handle,True,'nt',backend);runtime._file_lock(handle,False,'nt',backend)
        runtime._file_lock(handle,True,'posix',backend);runtime._file_lock(handle,False,'posix',backend)
        self.assertEqual(handle.positions,[(0,()),(0,()),(0,()),(0,())])
        self.assertEqual(backend.calls,[('locking',(7,1,1)),('locking',(7,2,1)),
                                        ('flock',(7,12)),('flock',(7,16))])
        lock=runtime._acquire_run_lock()
        try:
            code,stdout,stderr=self.invoke()
        finally:
            runtime._release_run_lock(lock)
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,'Studio run failed: Another studio run is already in progress\n')
        with patch.object(runtime,'_file_lock',side_effect=OSError(errno.EIO,'I/O error')), \
             self.assertRaises(OSError):
            runtime._acquire_run_lock()

    def test_output_permission_error_is_not_reported_as_success(self):
        def fail_output(p,out):raise PermissionError(errno.EACCES,'Permission denied')
        code,stdout,stderr=self.invoke(fail_output)
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,'Studio run failed: Permission denied\n')
        self.assertFalse((self.workspace/'out/latest.json').exists())
        self.assertFalse(json.loads((self.workspace/'.harness/verdict.json').read_text())['ready'])

    def test_result_permission_error_is_not_published(self):
        self.assert_write_failure(
            PermissionError(errno.EACCES,'Permission denied'),
            lambda path,data:path.name=='result.json')

    def test_read_only_latest_state_is_not_published(self):
        latest=(self.workspace/'out/latest.json').resolve()
        self.assert_write_failure(
            OSError(errno.EROFS,'Read-only file system'),
            lambda path,data:path.resolve()==latest and data.get('id'))

    def test_disk_full_final_state_is_not_published(self):
        verdict=(self.workspace/'.harness/verdict.json').resolve()
        self.assert_write_failure(
            OSError(errno.ENOSPC,'No space left on device'),
            lambda path,data:path.resolve()==verdict and data.get('ready') is True)

    def test_first_run_final_state_failure_removes_provisional_latest(self):
        verdict=(self.workspace/'.harness/verdict.json').resolve();real=runtime.atomic_json;raised=[]
        def fail_once(path,data):
            if not raised and Path(path).resolve()==verdict and data.get('ready') is True:
                raised.append(path);raise OSError(errno.ENOSPC,'No space left on device')
            return real(path,data)
        with patch.object(runtime,'atomic_json',side_effect=fail_once):
            code,stdout,stderr=self.invoke()
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,'Studio run failed: No space left on device\n')
        self.assertFalse((self.workspace/'out/latest.json').exists())
        self.assertEqual(runtime.previous_runs(),[])

    def test_failure_verdict_write_is_best_effort(self):
        verdict=(self.workspace/'.harness/verdict.json').resolve();real=runtime.atomic_json
        def fail(path,data):
            path=Path(path).resolve()
            if path.name=='result.json':raise PermissionError(errno.EACCES,'Permission denied')
            if path==verdict and data.get('phases',[{}])[0].get('state')=='failed':
                raise OSError(errno.ENOSPC,'No space left on device')
            return real(path,data)
        with patch.object(runtime,'atomic_json',side_effect=fail):
            code,stdout,stderr=self.invoke()
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,'Studio run failed: Permission denied\n')
        self.assertFalse(json.loads((self.workspace/'.harness/verdict.json').read_text())['ready'])

    def test_persistent_state_failures_leave_provisional_result_untrusted(self):
        self.call();latest=self.workspace/'out/latest.json';before=latest.read_bytes()
        prior=json.loads(before)['id'];verdict=(self.workspace/'.harness/verdict.json').resolve()
        real_json=runtime.atomic_json;real_write=runtime.atomic_write
        def fail_state(path,data):
            if Path(path).resolve()==verdict and (data.get('ready') is True or data.get('phases',[{}])[0].get('state')=='failed'):
                raise OSError(errno.ENOSPC,'No space left on device')
            return real_json(path,data)
        def fail_restore(path,data):
            if Path(path).resolve()==latest.resolve() and data==before:
                raise OSError(errno.EROFS,'Read-only file system')
            return real_write(path,data)
        with patch.object(runtime,'atomic_json',side_effect=fail_state),patch.object(runtime,'atomic_write',side_effect=fail_restore):
            code,stdout,stderr=self.invoke()
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,'Studio run failed: No space left on device\n')
        self.assertNotEqual(json.loads(latest.read_text())['id'],prior)
        self.assertEqual([row['id'] for row in runtime.previous_runs()],[prior])
        self.assertFalse(json.loads((self.workspace/'.harness/verdict.json').read_text())['ready'])

    def test_lost_publication_ownership_cannot_report_success(self):
        with patch.object(runtime,'_owns_verdict',return_value=False):
            code,stdout,stderr=self.invoke()
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,"Studio run failed: Another studio run replaced this run's state\n")
        self.assertFalse((self.workspace/'out/latest.json').exists())

    def test_concurrent_latest_is_not_rolled_back(self):
        latest=self.workspace/'out/latest.json';other={'id':'another-run'}
        def lose_ownership(*args):
            latest.write_text(json.dumps(other));return False
        with patch.object(runtime,'_owns_verdict',side_effect=lose_ownership):
            code,stdout,stderr=self.invoke()
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,"Studio run failed: Another studio run replaced this run's state\n")
        self.assertEqual(json.loads(latest.read_text()),other)

    def test_unreadable_provisional_latest_remains_untrusted(self):
        self.call();prior=runtime.previous_runs()[0]['id'];latest=(self.workspace/'out/latest.json').resolve()
        verdict=(self.workspace/'.harness/verdict.json').resolve();real_json=runtime.atomic_json;real_read=runtime._read_json
        failed=[]
        def fail_final(path,data):
            if not failed and Path(path).resolve()==verdict and data.get('ready') is True:
                failed.append(path);raise OSError(errno.ENOSPC,'No space left on device')
            return real_json(path,data)
        def unreadable(path):
            if Path(path).resolve()==latest:raise PermissionError(errno.EACCES,'Permission denied')
            return real_read(path)
        with patch.object(runtime,'atomic_json',side_effect=fail_final),patch.object(runtime,'_read_json',side_effect=unreadable):
            code,stdout,stderr=self.invoke()
        self.assertEqual(code,1);self.assertNotIn('Ready:',stdout)
        self.assertEqual(stderr,'Studio run failed: No space left on device\n')
        self.assertEqual([row['id'] for row in runtime.previous_runs()],[prior])

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(RunnerTests))
    if coverage:
        coverage.stop(); coverage.json_report(outfile=str(Path(__file__).resolve().parent.parent/'test-results/runtime-python-coverage.json'))
    sys.exit(not result.wasSuccessful())
