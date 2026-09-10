// Source-level checks; does not imply browser or visual acceptance.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const version=process.argv[2]||'v1.7';
assert.match(version,/^v\d+\.\d+(?:\.\d+)?$/);
const folder=path.join(__dirname,'../prototype',version),final=fs.readFileSync(path.join(folder,`留白-${version}-定稿.html`),'utf8');
for(const file of fs.readdirSync(folder).filter(f=>f.endsWith('.html'))){const html=fs.readFileSync(path.join(folder,file),'utf8');for(const [i,m] of [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].entries()){if(m[0].includes('type="application/json"')){JSON.parse(m[1]);continue;}new vm.Script(m[1],{filename:file+':'+i});}}
const fn=final.match(/function menuTask\(\)\s*\{[\s\S]*?\n\}/)?.[0];assert(fn,'Missing menuTask');
const ctx={prefs:{},timers:[],remaining:t=>t.left,save:()=>{}};vm.createContext(ctx);vm.runInContext(fn,ctx);
const task=(id,time,state='running')=>({id,runSince:time,state,left:1000});
assert.equal(ctx.menuTask(),undefined);ctx.timers=[task('a',1)];assert.equal(ctx.menuTask().id,'a');
ctx.timers.push(task('b',2));assert.equal(ctx.menuTask().id,'a');ctx.timers.reverse();assert.equal(ctx.menuTask().id,'a');
ctx.prefs.menuTaskId='b';assert.equal(ctx.menuTask().id,'b');ctx.timers[0].state='paused';assert.equal(ctx.menuTask().id,'a');
ctx.timers[0].state='running';assert.equal(ctx.menuTask().id,'a');ctx.timers[1].left=0;assert.equal(ctx.menuTask().id,'b');
ctx.timers=[];assert.equal(ctx.menuTask(),undefined);assert.equal(ctx.prefs.menuTaskId,null);
assert(!/id="(?:create|independentCreate)"|const variants\s*=|bLayout\s*===/.test(final),'Unselected creation/comparison branch remains');
assert.match(final,/reminder:\s*["']light["']/);assert.match(final,/level:\s*t.reminder/);assert.match(final,/data-sort-handle/);
console.log(version+': all HTML scripts parse; menu selection scenarios pass; finalized entry checks pass. Browser acceptance remains separate.');
const eventBlock=final.match(/\$\("#timers"\)\.onclick = e => \{[\s\S]*?\n\};/)[0];
const area={};ctx.$=()=>area;ctx.render=()=>{};ctx.tick=()=>{};ctx.showAlert=()=>{};ctx.alerts=[];
vm.runInContext(eventBlock,ctx);
const act=(id,action)=>area.onclick({target:{closest:()=>({dataset:{action},closest:()=>({dataset:{id}})})}});
ctx.timers=[{id:'a',state:'ready',total:60000,remaining:60000,left:60000,reminder:'light'},task('b',2)];
act('a','intensity');assert.equal(ctx.timers[0].reminder,'medium');act('a','intensity');assert.equal(ctx.timers[0].reminder,'strong');act('a','intensity');assert.equal(ctx.timers[0].reminder,'light');
act('a','toggle');assert.equal(ctx.timers[0].state,'running');act('a','pin');assert.equal(ctx.prefs.menuTaskId,'a');act('a','toggle');assert.equal(ctx.timers[0].state,'paused');act('a','restart');assert.equal(ctx.timers[0].state,'ready');assert.equal(ctx.timers[0].remaining,60000);
ctx.prefs.menuTaskId='b';act('a','pin');assert.equal(ctx.prefs.menuTaskId,'b');
ctx.alerts=[{id:'a'},{id:'b'}];act('a','delete');assert.equal(ctx.timers.length,1);assert.equal(ctx.alerts.length,1);assert.equal(ctx.alerts[0].id,'b');
console.log('Task start/pause/reset/delete, reminder cycling, and non-running menu selection checks pass.');

// v1.6 cleanup regression: :is(a,b) is OR, not a list of required attributes.
// Preserve the accepted card layout and palette swatches from the archived reference.
if(version==='v1.6'){
 const reference=fs.readFileSync(path.join(folder,'留白-v1.6-方案存档.html'),'utf8');
 const cssOf=html=>[...html.matchAll(/<style>([\s\S]*?)<\/style>/g)].map(m=>m[1]).join('\n');
 const refCSS=cssOf(reference), finalCSS=cssOf(final);
 const selectors=[
 'body:is([data-group="3"],[data-group="4"])[data-layout] .timer.optCard',
 'body:is([data-group="3"],[data-group="4"])[data-layout] .optCard .timerHead',
 'body:is([data-group="3"],[data-group="4"])[data-layout] .optCard .digits',
 'body:is([data-group="3"],[data-group="4"])[data-layout] .optCard .actions button',
 'body:is([data-group="3"],[data-group="4"])[data-layout] .optCard button svg',
 'body:is([data-group="3"],[data-group="4"])[data-layout="horizon"] .optCard .actions',
 'body:is([data-group="3"],[data-group="4"])[data-layout="horizon"] .optCard .actions .play',
 'body:is([data-group="3"],[data-group="4"])[data-layout="horizon"] .optCard .actions .restart',
 'body:is([data-colors="before"],[data-colors="five"],[data-colors="after"]) .eightDots',
 'body:is([data-colors="before"],[data-colors="five"],[data-colors="after"]) .eightDots i',
 '#settingsPage .paletteOptions button',
 '#settingsPage .eightDots'
 ];
 for(const selector of selectors){const start=refCSS.indexOf(selector+'{');assert(start>=0,'Reference missing: '+selector);const block=refCSS.slice(start,refCSS.indexOf('}',start)+1);assert(finalCSS.includes(block),'Accepted CSS removed or altered: '+selector);}
 console.log('12 accepted card/settings CSS rules match the scheme archive, including shared :is selectors.');
}

if (version === 'v1.7') {
    assert(!/comparisonKey|applyComparison|theme-review|data-capsule|capsuleActivity/.test(final), 'Comparison code remains');
    assert.match(final, /prefs\.autoTheme \?\?= true/);
    const appearance = final.match(/function applyAppearance\(\) \{[\s\S]*?\n\}/)[0];
    const indicators = final.match(/function updateFocusIndicator\(\) \{[\s\S]*?\n\}/)[0];
    let systemDark = true;
    const buttons = ['light','dark','auto'].map(mode => ({dataset:{mode},setAttribute(k,v){this[k]=v}}));
    const body = {dataset:{}};
    const test = {prefs:{},document:{body,querySelectorAll:()=>buttons},matchMedia:()=>({matches:systemDark})};
    vm.runInNewContext(appearance+'\napplyAppearance();',test);
    assert.equal(body.dataset.style,'dark');
    assert.equal(buttons[2]['aria-pressed'],'true');
    test.prefs={autoTheme:false,darkTheme:false};
    vm.runInNewContext(appearance+'\napplyAppearance();',test);
    assert.equal(body.dataset.style,'native');
    test.prefs={autoTheme:true};systemDark=false;
    vm.runInNewContext(appearance+'\napplyAppearance();',test);
    assert.equal(body.dataset.style,'native');
    const properties={},children={};
    const capsule={style:{setProperty:(k,v)=>properties[k]=v},querySelector:s=>children[s] ||= {},setAttribute(){}};
    let active={id:'a',name:'Task',total:60000,left:60000};
    const display={document:{body,fullscreenElement:null,querySelector:()=>({})},location:{search:'?fullscreen=1'},URLSearchParams,$:()=>capsule,menuTask:()=>active,remaining:t=>t.left,fmt:String,getComputedStyle:()=>({getPropertyValue:()=> '#123456'})};
    for (const [left, angle] of [[60000,'0deg'],[30000,'180deg'],[0,'360deg']]) {
        active.left=left;vm.runInNewContext(indicators+'\nupdateFocusIndicator();',display);
        assert.equal(properties['--focus-elapsed-angle'],angle);
    }
    assert.equal(properties['--indicator-tone'],'#123456');
    active=null;vm.runInNewContext(indicators+'\nupdateFocusIndicator();',display);assert(capsule.hidden);
    active={id:'b',name:'Next',total:60000,left:40000};display.location.search='';
    vm.runInNewContext(indicators+'\nupdateFocusIndicator();',display);assert(capsule.hidden);
    display.document.fullscreenElement={};vm.runInNewContext(indicators+'\nupdateFocusIndicator();',display);
    assert(!capsule.hidden);assert.equal(children['.focusName'].textContent,'Next');
    console.log('v1.7: default auto/manual/system appearance, fullscreen visibility, task handoff/color and elapsed ring checks pass.');
}
