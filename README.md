# 大肥鱼九色歌词气泡（根目录平铺版）

所有文件都放在仓库根目录，**不需要手动建子文件夹**；`Makefile` 会在编译前自动生成 Theos 需要的 `layout/` 结构。

## 仓库里应该有这 5 个文件

```
Tweak.x
Makefile
control
LyricBubble.plist
build.yml          <-- 这个要放到 .github/workflows/ 下（见下）
```

## 手机上传技巧

GitHub 网页「新建文件」时，文件名输入框可以直接写**带斜杠的完整路径**，会自动建目录：

- 新建文件，名字填 `.github/workflows/build.yml`，内容粘贴 `build.yml` 的全部内容；
- 其余 4 个文件直接放根目录即可。

（如果你连这个都不想建，也可以把 `build.yml` 放根目录，然后在网页上先建一个 `.github/workflows/build.yml` 再把内容贴过去。）

## 编译

- 推上去后进入 Actions → `build-deb` → Run workflow；
- 结束后在该次运行页面的 Artifacts 下载 `LyricBubble-deb`，解压得 `.deb`；
- Sileo 安装 → respring。

## 调参（Tweak.x 顶部）

`kBubbleYRatio` 位置比例（0.70）、`kSideMargin`（24）、`kBubbleHeight`（52）、`kCornerRadius`（16）、`kFontSize`（17）、`kRefresh`（0.5 秒）。

## 自检

装完看 `/var/mobile/Documents/lyricbubble.log`：

- 无文件 = 没注入
- `dylib loaded` = 注入成功
- `setup ok, window=` = 视图已建
- `line: ...` = 正在显示歌词
