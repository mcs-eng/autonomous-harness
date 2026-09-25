import test from 'node:test';
import assert from 'node:assert/strict';
import { DEFAULT_CONFIG, validateConfig } from '../lib/fleet.mjs';
import { nvidiaSmiInvocation, parseNvidiaSmi } from '../lib/sensors.mjs';

const source = {
  id: 'bran-gpu', type: 'nvidia-smi-ssh', engineEndpoint: 'http://bran:11434/v1/', host: 'hermes@bran',
  sshBinary: '/mnt/c/Windows/System32/OpenSSH/ssh.exe', identityFile: 'C:\\Users\\operator\\.ssh\\id_ed25519', gpuIndex: 0,
};

test('sensor configuration accepts Windows SSH custody and rejects ambiguous or ignored settings',()=>{
  const config=validateConfig({...DEFAULT_CONFIG,grid:'home',sensors:[source]});
  assert.equal(config.sensors[0].engineEndpoint,'http://bran:11434/v1');
  assert.equal(config.sensors[0].identityFile,'C:\\Users\\operator\\.ssh\\id_ed25519');
  for(const bad of [
    {...source,type:'shell'}, {...source,sshBinary:'ssh.exe'}, {...source,identityFile:'id_ed25519'},
    {...source,engineEndpoint:'http://user:secret@bran:11434/v1'}, {...source,engineEndpoint:'http://bran:11434/v1?token=secret'},
    {...source,host:'-proxy@bran'}, {...source,command:'nvidia-smi'},
  ]) assert.throws(()=>validateConfig({...DEFAULT_CONFIG,sensors:[bad]}));
  assert.throws(()=>validateConfig({...DEFAULT_CONFIG,sensors:[source,{...source}]}),/unique/);
  assert.throws(()=>validateConfig({...DEFAULT_CONFIG,sensors:[source,{...source,id:'other'}]}),/Only one sensor/);
});

test('null and omitted machine and sensor ids are rejected',()=>{
  const machine={transport:'local'};
  const sensorWithoutId={...source};
  delete sensorWithoutId.id;
  for(const bad of [
    {...DEFAULT_CONFIG,machines:[{...machine,id:null}]},
    {...DEFAULT_CONFIG,machines:[machine]},
    {...DEFAULT_CONFIG,machines:[{...machine,id:7}]},
    {...DEFAULT_CONFIG,sensors:[{...source,id:null}]},
    {...DEFAULT_CONFIG,sensors:[sensorWithoutId]},
  ]){
    assert.throws(()=>validateConfig(bad),/unique, simple id/);
  }
});

test('sensor invocation is a fixed nvidia-smi query with strict noninteractive SSH',()=>{
  const call=nvidiaSmiInvocation(validateConfig({...DEFAULT_CONFIG,sensors:[source]}).sensors[0]);
  assert.equal(call.file,source.sshBinary);
  assert.ok(call.args.includes('BatchMode=yes'));assert.ok(call.args.includes('IdentitiesOnly=yes'));assert.ok(call.args.includes('StrictHostKeyChecking=yes'));
  assert.ok(call.args.includes(source.identityFile));assert.equal(call.args.at(-1),'--format=csv,noheader,nounits');
  assert.ok(call.args.includes('--id=0'));assert.ok(call.args.some(arg=>arg.startsWith('--query-gpu=name,memory.total')));
  assert.deepEqual(call.args.slice(call.args.indexOf('--')+1),[source.host,'nvidia-smi','--id=0',call.args.at(-2),'--format=csv,noheader,nounits']);
});

test('sensor parser preserves zeroes and refuses implicit multi-GPU attribution',()=>{
  const row='NVIDIA RTX 2000 Ada Generation, 16380, 9859, 6083, 0, 31, 20.50, 70.00\n';
  assert.deepEqual(parseNvidiaSmi(source,row),{name:'NVIDIA RTX 2000 Ada Generation',memoryTotalMb:16380,memoryUsedMb:9859,memoryFreeMb:6083,utilizationPct:0,temperatureC:31,powerW:20.5,powerLimitW:70});
  assert.throws(()=>parseNvidiaSmi({...source,gpuIndex:undefined},row+row),/multiple GPUs/);
  assert.throws(()=>parseNvidiaSmi(source,'GPU, , 0, 0, 0, 30, N/A, N/A'),/missing/);
  assert.throws(()=>parseNvidiaSmi(source,'GPU, 10, 1, 9, 101, 30, N/A, N/A'),/above 100/);
  assert.throws(()=>parseNvidiaSmi(source,'GPU, 10, 11, 0, 0, 30, N/A, N/A'),/inconsistent memory/);
});
