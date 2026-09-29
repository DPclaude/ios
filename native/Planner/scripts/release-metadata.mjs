import { statSync, mkdirSync, copyFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export function releaseMetadata({ version, ipa, notes, date = new Date().toISOString() }) {
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) throw new Error('Expected numeric major.minor.patch version');
  const size = statSync(ipa).size;
  if (size === 0) throw new Error('IPA is empty');
  const downloadURL = `https://github.com/DPclaude/ios/releases/download/native-v${version}/Planner.ipa`;
  const update = { version, downloadURL, notes };
  const source = {
    name: '计划本', identifier: 'com.dpclaude.planner.source',
    subtitle: '原生计划本 · 免费个人安装',
    website: 'https://github.com/DPclaude/ios',
    apps: [{
      name: 'Planner', bundleIdentifier: 'com.dpclaude.planner', developerName: 'DPclaude',
      localizedDescription: '中文原生计划本，桌面点勾直接完成计划，每条计划可设置通知提醒。数据保存在本机。',
      iconURL: 'https://raw.githubusercontent.com/DPclaude/ios/main/icon-512-v3.png',
      tintColor: '#ED8627',
      versions: [{ version, date, localizedDescription: notes, downloadURL, size, minOSVersion: '17.0' }],
      appPermissions: { entitlements: ['com.apple.security.application-groups'], privacy: {} }
    }], news: []
  };
  return { source, update };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [version, ipa, output = 'build/distribution'] = process.argv.slice(2);
  const notes = '桌面小圆圈支持即时勾选反馈，完成项分组保留在下方；点组件空白处新增计划。App 内拖动排序同步组件，重要计划显示红字。移除默认分类选项和组件底部说明、进度条，提醒设置提前，通知直接显示任务内容，减少重复安排提醒。更新时保留小组件扩展，并打开 App 一次。';
  const { source, update } = releaseMetadata({ version, ipa, notes });
  mkdirSync(output, { recursive: true });
  copyFileSync(ipa, join(output, 'Planner.ipa'));
  writeFileSync(join(output, 'planner-source.json'), JSON.stringify(source, null, 2) + '\n');
  writeFileSync(join(output, 'planner-update.json'), JSON.stringify(update, null, 2) + '\n');
  writeFileSync(join(output, 'release-notes.md'), notes + '\n\n使用自己的 Apple 账户通过 SideStore 签名安装。小组件同步和 iOS 27.0 需在真机验证。\n');
  console.log(`Release metadata ready: ${version}, ${source.apps[0].versions[0].size} bytes`);
}
