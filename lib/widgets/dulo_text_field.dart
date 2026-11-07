import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Text field with optional label above it and a show/hide eye for passwords.
class DuloTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool password;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const DuloTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.password = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  State<DuloTextField> createState() => _DuloTextFieldState();
}

class _DuloTextFieldState extends State<DuloTextField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    final c = context.dulo;
    final field = TextField(
      controller: widget.controller,
      obscureText: widget.password && _hide,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLines: widget.password ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(color: c.ink, fontSize: 16),
      cursorColor: c.accent,
      decoration: InputDecoration(
        hintText: widget.hint,
        errorText: widget.errorText,
        counterText: '',
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, color: c.muted),
        suffixIcon: widget.password
            ? IconButton(
                icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: c.muted),
                onPressed: () => setState(() => _hide = !_hide),
              )
            : null,
      ),
    );
    if (widget.label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(widget.label!, style: TextStyle(color: c.muted, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        field,
      ],
    );
  }
}
