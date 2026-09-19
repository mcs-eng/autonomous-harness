import { spawn } from 'node:child_process';

const QUERY = 'name,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu,power.draw,power.limit';
const number = (value, required = false) => {
  const raw = String(value).trim();
  if (!raw) throw new Error('NVIDIA sensor returned a missing measurement.');
  const parsed = Number(raw);
  if (Number.isFinite(parsed) && parsed >= 0) return parsed;
  if (!required && /^(?:n\/a|not supported|\[not supported\])$/i.test(raw)) return null;
  throw new Error('NVIDIA sensor returned a non-numeric measurement.');
};

export function parseNvidiaSmi(source, stdout) {
  const rows = String(stdout).trim().split(/\r?\n/).filter(Boolean);
  if (rows.length !== 1) {
    if (rows.length > 1 && source.gpuIndex === undefined) throw new Error('NVIDIA sensor found multiple GPUs; configure gpuIndex explicitly.');
    throw new Error('NVIDIA sensor did not return exactly one GPU.');
  }
  const fields = rows[0].split(',').map(value => value.trim());
  if (fields.length !== 8 || !fields[0]) throw new Error('NVIDIA sensor returned an unexpected response.');
  const memoryTotalMb = number(fields[1], true), memoryUsedMb = number(fields[2], true), memoryFreeMb = number(fields[3], true);
  if (memoryUsedMb > memoryTotalMb || memoryFreeMb > memoryTotalMb) throw new Error('NVIDIA sensor returned inconsistent memory measurements.');
  const utilizationPct = number(fields[4], true);
  if (utilizationPct > 100) throw new Error('NVIDIA sensor returned utilization above 100 percent.');
  return {
    name: fields[0].replace(/[\u0000-\u001f\u007f]/g, ' ').slice(0, 240), memoryTotalMb, memoryUsedMb, memoryFreeMb,
    utilizationPct, temperatureC: number(fields[5], true),
    powerW: number(fields[6]), powerLimitW: number(fields[7]),
  };
}

export function nvidiaSmiInvocation(source) {
  const args = ['-T', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', '-o', 'ConnectionAttempts=1'];
  if (source.port) args.push('-p', String(source.port));
  if (source.identityFile) args.push('-i', source.identityFile);
  args.push('--', source.host, 'nvidia-smi');
  if (source.gpuIndex !== undefined) args.push(`--id=${source.gpuIndex}`);
  args.push(`--query-gpu=${QUERY}`, '--format=csv,noheader,nounits');
  return { file: source.sshBinary || 'ssh', args };
}

export function readNvidiaSmiSensor(source, { spawnImpl = spawn, timeoutMs = 8000 } = {}) {
  const call = nvidiaSmiInvocation(source);
  return new Promise(resolve => {
    let stdout = '', stderrBytes = 0, finished = false, timer, child;
    const finish = result => { if (finished) return; finished = true; clearTimeout(timer); resolve({ ...result, observedAt: new Date().toISOString() }); };
    const stop = error => { try { child?.kill('SIGKILL'); } catch { /* already gone */ } finish({ ok: false, error }); };
    try { child = spawnImpl(call.file, call.args, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true }); }
    catch { finish({ ok: false, error: 'NVIDIA SSH sensor could not start.' }); return; }
    child.stdout?.setEncoding('utf8').on('data', chunk => {
      if (Buffer.byteLength(stdout) + Buffer.byteLength(chunk) > 64 * 1024) stop('NVIDIA SSH sensor output exceeded 64 KiB.');
      else stdout += chunk;
    });
    child.stderr?.on('data', chunk => { stderrBytes += chunk.length; if (stderrBytes > 64 * 1024) stop('NVIDIA SSH sensor output exceeded 64 KiB.'); });
    child.once('error', () => finish({ ok: false, error: 'NVIDIA SSH sensor could not start.' }));
    child.once('close', code => {
      if (finished) return;
      if (code !== 0) { finish({ ok: false, error: `NVIDIA SSH sensor failed (${code ?? 'signal'}).` }); return; }
      try { finish({ ok: true, value: parseNvidiaSmi(source, stdout) }); }
      catch (error) { finish({ ok: false, error: error.message }); }
    });
    timer = setTimeout(() => stop('NVIDIA SSH sensor timed out.'), timeoutMs);
  });
}
