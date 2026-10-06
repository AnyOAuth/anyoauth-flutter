// Generated standalone SDK checks. Canonical source: AnyOAuth/anyoauth.
import {spawn} from 'node:child_process';
import {mkdir} from 'node:fs/promises';
await mkdir('build',{recursive:true});
for(const command of [["dart","pub","get"],["dart","analyze"],["dart","run","test/models.dart"],["dart","compile","exe","test/conformance.dart","-o","build/conformance"],["node","conformance.test.mjs","build/conformance"]]){
  console.log('> '+command.join(' '));
  await new Promise((resolve,reject)=>{const child=spawn(command[0],command.slice(1),{stdio:'inherit'});child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(new Error(command[0]+' failed: '+code)));});
}
