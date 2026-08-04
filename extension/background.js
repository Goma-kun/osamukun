// ツールバーアイコンのクリックでサイドパネルを開く
chrome.sidePanel
  .setPanelBehavior({ openPanelOnActionClick: true })
  .catch((e) => console.error(e));
