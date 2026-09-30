import http2 from 'node:http2';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {setTimeout as sleep} from 'node:timers/promises';
import {createHash} from 'node:crypto';

const [mode, primaryURL, standbyURL, primaryPod, standbyPod] = process.argv.slice(2);
if (!['handover','partition'].includes(mode) || !standbyPod) throw new Error('usage: client.mjs handover|partition PRIMARY_URL STANDBY_URL PRIMARY_POD STANDBY_POD');
const context = process.env.KURA_SPEC98_CONTEXT;
if (!context) throw new Error('KURA_SPEC98_CONTEXT must explicitly identify the isolated staging context');
const kube = (...args) => execFileSync('kubectl',['--context',context,'-n','kura-spec98',...args],{encoding:'utf8'});
const sessions = [http2.connect(primaryURL),http2.connect(standbyURL)];
const vint = value => {const out=[]; do {let b=value&127;value=Math.floor(value/128);if(value)b|=128;out.push(b);} while(value);return Buffer.from(out);};
const field = (id,data) => {data=Buffer.from(data);return Buffer.concat([vint(id*8+2),vint(data.length),data]);};
const number = (id,value) => Buffer.concat([vint(id*8),vint(value)]);
const frame = body => {const header=Buffer.alloc(5);header.writeUInt32BE(body.length,1);return Buffer.concat([header,body]);};
function request(session,path,method='GET',body,grpc=false) {
  return new Promise((resolve,reject) => {
    const stream=session.request({':path':path,':method':method,...(grpc?{'content-type':'application/grpc','te':'trailers'}:body?{'content-type':'application/json'}:{})});
    let headers={},trailers={},chunks=[];
    stream.on('response',value=>headers=value);stream.on('trailers',value=>trailers=value);
    stream.on('data',chunk=>chunks.push(chunk));stream.on('error',reject);
    stream.on('end',()=>resolve({status:headers[':status'],grpc:trailers['grpc-status']??headers['grpc-status'],body:Buffer.concat(chunks)}));
    stream.end(body);
  });
}
const report = async url => (await (await fetch(`${url}/status/rollout`)).json()).serving_authority;
const capabilities = session => request(session,'/build.bazel.remote.execution.v2.Capabilities/GetCapabilities','POST',frame(field(1,'e2e')),true);
const key = `persistent-${Date.now()}`;
const query='?tenant_id=spec98-validation&namespace_id=e2e';
const write = session => request(session,`/api/cache/keyvalue${query}`,'PUT',JSON.stringify({cas_id:key,entries:[{value:key}]}));
let policyInstalled=false;
try {
  const before=await report(primaryURL),target=await report(standbyURL);
  assert.equal(before.valid,true);assert.equal(target.valid,false);
  assert.equal((await write(sessions[0])).status,204);
  assert.equal((await capabilities(sessions[0])).grpc,'0');
  const blob=Buffer.from(`grpc-persistent-${key}`);
  const hash=createHash('sha256').update(blob).digest('hex');
  const digest=Buffer.concat([field(1,hash),number(2,blob.length)]);
  const batch=Buffer.concat([field(1,'e2e'),field(2,Buffer.concat([field(1,digest),field(2,blob)]))]);
  const upload=await request(sessions[0],'/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchUpdateBlobs','POST',frame(batch),true);
  assert.equal(upload.grpc,'0');
  if(mode==='handover') {
    const id=`persistent-${Date.now()}`;
    kube('patch','kurainstance','kura-spec98','--type=merge','-p',JSON.stringify({spec:{plannedHandover:{id,podName:standbyPod,podUID:target.identity.pod_uid,incarnation:target.identity.incarnation}}}));
    let after;
    for(let i=0;i<120;i++){await sleep(1000);after=await report(standbyURL);if(after.valid&&after.epoch>before.epoch)break;}
    assert.equal(after.valid,true);assert.equal(after.epoch,before.epoch+1);
    const read=await request(sessions[1],`/api/cache/keyvalue/${key}${query}`);
    assert.equal(read.status,200);assert.equal(JSON.parse(read.body).entries[0].value,key);
    const blobRead=await request(sessions[1],'/google.bytestream.ByteStream/Read','POST',frame(field(1,`e2e/blobs/${hash}/${blob.length}`)),true);
    assert.equal(blobRead.grpc,'0');assert(blobRead.body.includes(blob));
    assert.equal((await write(sessions[0])).status,503);
    assert.notEqual((await capabilities(sessions[0])).grpc,'0');
    assert.equal((await write(sessions[1])).status,204);
    console.log(JSON.stringify({mode,epoch:after.epoch,retainedHTTP:true,retainedGRPC:true,oldPersistentHTTPRejected:true,oldPersistentGRPCRejected:true}));
  } else {
    kube('label','pod',primaryPod,'spec98.tuist.dev/api-partition=true','--overwrite');
    policyInstalled=true;
    const observations=[];
    for(let i=0;i<18;i++){await sleep(2000);const observed=await report(primaryURL);const http=await write(sessions[0]);const grpc=await capabilities(sessions[0]);observations.push({second:(i+1)*2,valid:observed.valid,expires:observed.observed?.expires_ms,http:http.status,grpc:grpc.grpc??String(grpc.status)});}
    console.log(JSON.stringify({mode,observations}));
    assert(observations.slice(-5).every(x=>!x.valid&&x.http===503&&x.grpc!=='0'));
    assert.equal((await report(standbyURL)).valid,false,'partition alone promoted standby');
    assert(observations.slice(-5).every(x=>x.expires===observations.at(-1).expires),'API partition did not stop renewal observations');
    console.log(JSON.stringify({mode,epoch:before.epoch,noTimeoutPromotion:true,observations}));
  }
} finally {
  if(policyInstalled) kube('label','pod',primaryPod,'spec98.tuist.dev/api-partition-');
  for(const session of sessions)session.close();
}
