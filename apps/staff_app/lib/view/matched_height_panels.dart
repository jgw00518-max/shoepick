import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 왼쪽 패널을 자연 높이로 배치한 뒤 오른쪽 패널에 그 실제 높이를 적용한다.
class MatchedHeightPanels extends MultiChildRenderObjectWidget {
  MatchedHeightPanels({
    super.key,
    required Widget first,
    required Widget second,
  }) : super(children: [first, second]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MatchedHeightPanelsBox();
}

class _PanelParentData extends ContainerBoxParentData<RenderBox> {}

class _MatchedHeightPanelsBox extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  static const gap = 16.0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _PanelParentData();
    }
  }

  double firstWidth(BoxConstraints constraints) =>
      (constraints.maxWidth - gap) * .6;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final firstSize = firstChild!.getDryLayout(
      BoxConstraints.tightFor(width: firstWidth(constraints)),
    );
    return constraints.constrain(Size(constraints.maxWidth, firstSize.height));
  }

  @override
  void performLayout() {
    final first = firstChild!;
    final second = lastChild!;
    final width = firstWidth(constraints);
    first.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    second.layout(
      BoxConstraints.tightFor(
        width: constraints.maxWidth - width - gap,
        height: first.size.height,
      ),
      parentUsesSize: true,
    );
    (first.parentData! as ContainerBoxParentData<RenderBox>).offset =
        Offset.zero;
    (second.parentData! as ContainerBoxParentData<RenderBox>).offset = Offset(
      width + gap,
      0,
    );
    size = constraints.constrain(Size(constraints.maxWidth, first.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset =
        (child.parentData! as ContainerBoxParentData<RenderBox>).offset;
    transform.multiply(Matrix4.translationValues(offset.dx, offset.dy, 0));
  }
}
