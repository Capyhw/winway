const views = {
  move: {src:'move-between-tabs.png', title:'两个目录，一个窗口。', description:'剪切、切换标签、粘贴。也支持拖拽移动，悬停标签自动切换，每个标签保留独立的浏览状态。', alt:'项目计划.txt 已从项目资料移入交付文件，状态栏显示成功 1'},
  search: {src:'search.png', title:'子文件夹里的文件，也能找到。', description:'输入 ext:txt，筛出当前目录与子文件夹中的文本文件；也可以使用模糊名称、type:image 或 grep:内容。', alt:'FSearch 使用 ext:txt 查找文本文件，结果包含参考资料子文件夹内的项目需求.txt'},
  menu: {src:'context-menu.png', title:'常用操作，就在右键里。', description:'按用途分组的文件菜单，支持打开方式、快捷键提示和 macOS 系统文件服务。', alt:'Winway 文件右键菜单，包含打开方式、剪切、复制、重命名、移到废纸篓与 Services'},
  keyboard: {src:'keyboard.png', title:'用哪套习惯，你来决定。', description:'Windows 与 macOS 两套预设分别保存。单独修改某个按键，或恢复默认；录入时提示冲突。', alt:'Winway 键盘设置，Windows 预设选中，显示打开、重命名、复制、剪切和粘贴快捷键'}
};
const buttons = [...document.querySelectorAll('[data-view]')];
const screenshot = document.querySelector('#gallery-image');
buttons.forEach(button => button.addEventListener('click', () => {
  const view = views[button.dataset.view];
  buttons.forEach(item => item.setAttribute('aria-pressed', String(item === button)));
  screenshot.src = `assets/${view.src}`;
  screenshot.alt = view.alt;
  screenshot.parentElement.classList.toggle('is-keyboard', button.dataset.view === 'keyboard');
  document.querySelector('#gallery-title').textContent = view.title;
  document.querySelector('#gallery-description').textContent = view.description;
}));
