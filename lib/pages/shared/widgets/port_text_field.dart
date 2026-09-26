import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/pages/theme/font.dart';

/// A TCP port input. Empty text is reported as 0 so the draft stays typed;
/// range checks belong to the controller that validates the draft.
class PortTextField extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final String? hint;

  const PortTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.hint,
  });

  @override
  State<PortTextField> createState() => _PortTextFieldState();
}

class _PortTextFieldState extends State<PortTextField> {
  late final controller = TextEditingController(text: _text(widget.value));

  static String _text(int value) => value > 0 ? '$value' : '';

  @override
  void didUpdateWidget(covariant PortTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = _text(widget.value);
    if (controller.text != text) controller.text = text;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      TextField(
        controller: controller,
        onChanged: (text) => widget.onChanged(int.tryParse(text) ?? 0),
        enabled: widget.enabled,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        autocorrect: false,
        enableSuggestions: false,
        style: AppTypography.settingsInput,
        decoration: InputDecoration(labelText: widget.label),
      ),
      if (widget.hint != null)
        Text(widget.hint!, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
