import 'package:flutter/material.dart';

class IntuitTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? helperText;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final String? errorText;
  final bool enabled;

  const IntuitTextField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.focusNode,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.suffixIcon,
    this.errorText,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      enabled: enabled,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        errorText: errorText,

        floatingLabelBehavior: FloatingLabelBehavior.auto,

        filled: true,
        fillColor: Colors.white,
        isDense: true,

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6), // ✅ Intuit radius
          borderSide: const BorderSide(color: Color(0xFF8D9096)),
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF8D9096)),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(
            color: Color(0xFF0077C5), // ✅ Intuit focus blue
            width: 1.5,
          ),
        ),

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFD52B1E)),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFD52B1E), width: 1.5),
        ),

        labelStyle: TextStyle(
          color: enabled
              ? const Color(0xFF6B6C72) // normal Intuit label
              : const Color(0xFFBABEC5), // disabled Intuit label
          fontWeight: FontWeight.w400,
        ),

        helperStyle: TextStyle(
          color: enabled ? const Color(0xFF6B6C72) : const Color(0xFFBABEC5),
          fontSize: 12,
        ),

        suffixIcon: suffixIcon,
      ),
    );
  }
}
