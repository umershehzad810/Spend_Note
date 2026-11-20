import 'package:material_ui/material_ui.dart';

/// Some Android emulators report a desktop-sized logical width at phone aspect
/// ratios. Keep a readable phone canvas, including navigator overlays/keyboard.
class PhoneViewport extends StatelessWidget {
  const PhoneViewport({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    if (size.width <= 600 || size.height / size.width < 1.6) return child;
    final scale = size.width / 440;
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: 440,
        height: size.height / scale,
        child: MediaQuery(
          data: media.copyWith(
            size: Size(440, size.height / scale),
            devicePixelRatio: media.devicePixelRatio * scale,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
            systemGestureInsets: media.systemGestureInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}

ThemeData spendNoteTheme({bool dark = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF16735B),
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: dark ? const Color(0xFF182320) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF101916)
        : const Color(0xFFF3F6F4),
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF101916) : const Color(0xFFF3F6F4),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF23332C) : const Color(0xFFEDF2EE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.never,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: dark ? const Color(0xFF274D3C) : const Color(0xFFD9EFE3),
      height: 76,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: scheme.surface,
      selectedColor: dark ? const Color(0xFF274D3C) : const Color(0xFFD9EFE3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .4),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF16735B),
      foregroundColor: Colors.white,
      elevation: 3,
    ),
  );
}
