{
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require('node:path').join(__dirname, '../sw.js'), 'utf8');

function worker() {
  const handlers = {}, deleted = [];
  const context = {
    URL, fetch: async () => { throw new Error('offline'); },
    caches: {
      keys: async () => ['planner-v4', 'planner-v5', 'other-app-v1'],
      delete: async key => { deleted.push(key); return true; },
      open: async () => ({addAll: async () => {}}),
      match: async () => undefined,
    },
    self: {location: new URL('https://example.test/ios/sw.js'), registration: {scope: 'https://example.test/ios/'},
      addEventListener: (type, fn) => handlers[type] = fn,
      skipWaiting() {}, clients: {claim: async () => {}}},
  };
  vm.runInNewContext(source, context);
  return {handlers, deleted};
}

test('activation preserves caches belonging to other apps', async () => {
  const w = worker(); let pending;
  w.handlers.activate({waitUntil: p => pending = p}); await pending;
  assert.ok(!w.deleted.includes('other-app-v1'));
  assert.ok(w.deleted.includes('planner-v4'));
});

test('root service worker leaves nested apps and external requests alone', () => {
  const w = worker();
  for (const url of ['https://example.test/ios/apps/timer/', 'https://cdn.example.test/a.js']) {
    let handled = false;
    w.handlers.fetch({request: {method: 'GET', url}, respondWith() { handled = true; }});
    assert.equal(handled, false, url);
  }
});

}
{
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];

// Exercise the existing data layer with an original planner-v1 backup.
function loadPlanner(data) {
  let stored = JSON.stringify(data);
  const context = {
    localStorage: {getItem(key) {assert.equal(key, 'planner-v1'); return stored;}, setItem(key, value) {assert.equal(key, 'planner-v1'); stored=value;}},
    Date: class extends Date {constructor(...args) {super(...(args.length ? args : ['2026-09-29T12:00:00']));}},
  };
  vm.runInNewContext(script.slice(0, script.indexOf('// ---------- state')) + '\nglobalThis.api={load,rollover,repeatItems,shift,getData:()=>db};})();', context);
  return context.api;
}

test('original saved tasks, notes and daily completions remain readable', () => {
  const old = {tasks:[{id:'a',text:'已有计划',date:'2026-09-29',cat:1,done:false,order:3}], notes:{'2026-09-29':'旧备忘'}, repeats:[{id:'r1',text:'阅读',cat:3,from:'2026-09-28'}], repeatDone:{'2026-09-29':['r1']}};
  const app = loadPlanner(old);
  assert.deepEqual(JSON.parse(JSON.stringify(app.getData())), old);
  assert.equal(app.repeatItems('2026-09-29')[0].done, true);
  assert.equal(app.repeatItems('2026-09-30')[0].done, false);
});

test('only overdue unfinished tasks roll forward; completed history is preserved', () => {
  const app = loadPlanner({tasks:[{id:'a',text:'待办',date:'2026-09-27',done:false},{id:'b',text:'完成',date:'2026-09-28',done:true},{id:'c',text:'未来',date:'2026-10-01',done:false}]});
  app.rollover();
  const tasks = app.getData().tasks;
  assert.equal(tasks[0].date, '2026-09-29');
  assert.equal(tasks[0].rolled, true);
  assert.equal(tasks[1].date, '2026-09-28');
  assert.equal(tasks[2].date, '2026-10-01');
});

test('week navigation crosses month and year boundaries', () => {
  const app = loadPlanner({tasks:[]});
  assert.equal(app.shift('2026-09-30', 1), '2026-10-01');
  assert.equal(app.shift('2026-12-31', 1), '2027-01-01');
  assert.equal(app.shift('2026-01-01', -1), '2025-12-31');
});

}
