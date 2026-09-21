// Browser regression against fictional telemetry. Uses the same opt-in browser runtime as browser.mjs.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createViewer } from '../viewer.mjs';
import { assemble } from '../lib/telemetry.mjs';
import { config, reads } from './fixtures.mjs';

if(!process.env.GRID_TEST_PLAYWRIGHT)throw new Error('Set GRID_TEST_PLAYWRIGHT to an installed Playwright entrypoint.');
const {chromium}=await import(pathToFileURL(process.env.GRID_TEST_PLAYWRIGHT).href);
const workspace=await mkdtemp(join(tmpdir(),'grid-motion-'));
let fixture={...assemble(config,reads),machines:[],operations:[]};
const viewer=createViewer({workspace,intervalMs:50,collect:async()=>fixture});
const port=await viewer.start();
let browser;
try {
  browser=await chromium.launch({headless:true,...(process.env.GRID_TEST_BROWSER?{executablePath:process.env.GRID_TEST_BROWSER}:{})});
  const page=await browser.newPage({viewport:{width:1440,height:900},reducedMotion:'no-preference'});
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  // Optional baseline script lets the regression demonstrate failure before the fix.
  if(process.env.GRID_TEST_APP)await page.route('**/app.js',route=>readFile(process.env.GRID_TEST_APP,'utf8').then(body=>route.fulfill({contentType:'text/javascript',body})));
  await page.addInitScript(()=>{
    const queued=new Map();let next=0;
    const probe=window.motionProbe={draws:0,resizeDraws:0,pending:()=>queued.size,step:()=>{
      const callbacks=[...queued.values()];queued.clear();
      for(const callback of callbacks)callback(performance.now());
    }};
    // Advance browser animation frames explicitly so cancellation is deterministic.
    window.requestAnimationFrame=callback=>{const id=++next;queued.set(id,callback);return id;};
    window.cancelAnimationFrame=id=>queued.delete(id);
    const clear=CanvasRenderingContext2D.prototype.clearRect;
    CanvasRenderingContext2D.prototype.clearRect=function(...args){probe.draws++;return clear.apply(this,args);};
    const Observe=window.ResizeObserver;
    window.ResizeObserver=class extends Observe{constructor(callback){super((...args)=>{const before=probe.draws;callback(...args);probe.resizeDraws+=probe.draws-before;});}};
    probe.visibility=hidden=>{
      Object.defineProperty(document,'hidden',{configurable:true,value:hidden});
      document.dispatchEvent(new Event('visibilitychange'));
    };
  });
  await page.goto(`http://127.0.0.1:${port}/`);await page.locator('.node').first().waitFor();
  const pending=()=>page.evaluate(()=>window.motionProbe.pending());
  const click=id=>page.evaluate(id=>document.getElementById(id).click(),id);
  const visibility=hidden=>page.evaluate(hidden=>window.motionProbe.visibility(hidden),hidden);
  assert.equal(await pending(),1,'active topology schedules one frame');
  await page.evaluate(()=>window.motionProbe.step());
  assert.equal(await pending(),1,'each frame schedules exactly one successor');

  await click('motion');
  assert.equal(await pending(),0,'Pause cancels the pending frame');
  assert.equal(await page.locator('#motion').innerText(),'Resume motion');
  assert.equal(await page.evaluate(()=>{const before=window.motionProbe.draws;window.motionProbe.step();return window.motionProbe.draws-before;}),0);
  const beforeData=await page.evaluate(()=>window.motionProbe.draws);
  fixture={...fixture,summary:{...fixture.summary,enginesOnline:3}};
  await page.waitForFunction(()=>document.getElementById('total-engines').textContent==='3',null,{polling:50});
  assert.ok(await page.evaluate(()=>window.motionProbe.draws)>beforeData,'paused telemetry still redraws');
  assert.ok(await page.evaluate(()=>{const before=window.motionProbe.draws;document.querySelector('.node').click();return window.motionProbe.draws>before;}),'paused selection still redraws');
  const beforeResize=await page.evaluate(()=>window.motionProbe.resizeDraws);
  await page.setViewportSize({width:1200,height:850});
  await page.waitForFunction(before=>window.motionProbe.resizeDraws>before,beforeResize,{polling:50});
  assert.equal(await pending(),0,'telemetry, selection and resize do not restart paused motion');
  await visibility(true);await visibility(false);
  assert.equal(await pending(),0,'becoming visible respects the pause preference');
  await click('motion');
  assert.equal(await pending(),1,'Resume schedules one frame');

  await visibility(true);assert.equal(await pending(),0,'hidden pages cancel motion');
  await visibility(false);await visibility(false);
  assert.equal(await pending(),1,'visibility resumes once without duplicate loops');
  await click('rack-button');assert.equal(await pending(),0,'Rack cancels motion');
  await visibility(true);await visibility(false);
  assert.equal(await pending(),0,'visible Rack stays still');
  await click('topology-button');await click('topology-button');
  assert.equal(await pending(),1,'Topology resumes once');
  await page.evaluate(()=>window.motionProbe.step());assert.equal(await pending(),1);

  await page.emulateMedia({reducedMotion:'reduce'});await page.reload();
  await page.locator('.node').first().waitFor();
  assert.equal(await pending(),0,'initial reduced motion starts without a frame');
  await click('motion');assert.equal(await pending(),1,'reduced-motion users can explicitly resume');
  assert.deepEqual(errors,[]);
  console.log('Grid motion passed: pause/resume, visibility, Rack/Topology, reduced motion, and event-driven redraws.');
} finally {
  await browser?.close();await viewer.close();await rm(workspace,{recursive:true,force:true});
}
