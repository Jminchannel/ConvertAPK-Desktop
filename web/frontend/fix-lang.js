const fs = require('fs');

// 读取文件
let content = fs.readFileSync('src/App.vue', 'utf8');

// 查找并替换问题行
const lines = content.split('\n');
for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes("code: 'zh-TW'")) {
    lines[i] = "  { code: 'zh-TW', label: '繁體中文' }";
    console.log('Fixed line', i + 1);
  }
}

// 写回文件
fs.writeFileSync('src/App.vue', lines.join('\n'), 'utf8');
console.log('File fixed successfully!');

