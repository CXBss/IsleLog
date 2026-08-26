import 'package:flutter/material.dart';

/// 一张图在网格/全屏查看器里的渲染方式。
///
/// 用构建器而不是 [ImageProvider]，是因为两个调用方的取图路径差别很大：
/// 主库的图可能在磁盘、也可能要带 Authorization 头去远端拉（`_AuthImage`），
/// 而隐私空间的图只以内存字节存在——落盘就违背了它存在的意义。
/// 共享的是布局和交互，不是图片加载。
class GridImageSource {
  final Widget Function({double? width, double? height, BoxFit fit}) build;

  /// 全屏查看时长按触发（保存到相册 / 分享 / 复制）。
  ///
  /// 传 null 表示**禁用导出**。隐私空间必须传 null——保存到系统相册等于把
  /// 私密照片明文写进公共图库，分享等于直接送出去，两者都会击穿隐私空间。
  final VoidCallback? onExport;

  const GridImageSource({required this.build, this.onExport});
}

/// 图片网格：1 张铺满、2 张并排、3 张及以上左大右双（第 3 张盖 "+N"）。
///
/// 从 memo_detail_page 的 _DetailImageGrid 抽出，布局逻辑逐像素保持一致。
class ImageGrid extends StatelessWidget {
  final List<GridImageSource> images;

  const ImageGrid({super.key, required this.images});

  void _open(BuildContext context, int index) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) =>
            ImageViewerPage(images: images, initialIndex: index),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Widget _tappable(
    BuildContext context,
    int index,
    BorderRadius radius, {
    double? width,
    double? height,
  }) {
    return GestureDetector(
      onTap: () => _open(context, index),
      child: ClipRRect(
        borderRadius: radius,
        child: images[index].build(
          width: width,
          height: height,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = images.length;
    if (count == 0) return const SizedBox.shrink();

    if (count == 1) {
      return _tappable(
        context,
        0,
        BorderRadius.circular(8),
        width: double.infinity,
        height: 220,
      );
    }

    if (count == 2) {
      return Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _tappable(
                context,
                i,
                BorderRadius.circular(8),
                height: 160,
              ),
            ),
          ],
        ],
      );
    }

    // 3 张及以上：左边一张大图，右边上下两张小图，第 3 张在超出时盖 "+N"
    return Row(
      children: [
        Expanded(
          child: _tappable(context, 0, BorderRadius.circular(8), height: 180),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 100,
          height: 180,
          child: Column(
            children: [
              Expanded(
                child: _tappable(
                  context,
                  1,
                  const BorderRadius.only(topRight: Radius.circular(8)),
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: GestureDetector(
                  onTap: () => _open(context, 2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(8),
                        ),
                        child: images[2].build(
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (count > 3)
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomRight: Radius.circular(8),
                          ),
                          child: ColoredBox(
                            color: Colors.black45,
                            child: Center(
                              child: Text(
                                '+${count - 3}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 全屏图片查看器：左右翻页 + 双指缩放，长按可导出（若来源允许）。
class ImageViewerPage extends StatefulWidget {
  final List<GridImageSource> images;
  final int initialIndex;

  const ImageViewerPage({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _ctrl = PageController(
    initialPage: widget.initialIndex,
  );
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: Stack(
          children: [
            PageView.builder(
              controller: _ctrl,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                final source = widget.images[i];
                return GestureDetector(
                  // 空实现拦住外层的“点击关闭”，让缩放手势正常工作
                  onTap: () {},
                  onLongPress: source.onExport,
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: source.build(fit: BoxFit.contain),
                    ),
                  ),
                );
              },
            ),
            if (widget.images.length > 1)
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.images.length,
                    (i) => Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _current ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
