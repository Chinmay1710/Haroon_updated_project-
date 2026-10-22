import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomMeasurementKeypad extends StatelessWidget {
  final int activeBoxNumber;
  final String currentValue;
  final ValueChanged<String> onInsertText;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  const CustomMeasurementKeypad({
    super.key,
    required this.activeBoxNumber,
    required this.currentValue,
    required this.onInsertText,
    required this.onBackspace,
    required this.onClear,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  void _handleFractionTap(String fraction) {
    HapticFeedback.lightImpact();
    final trimmed = currentValue.trim();
    if (trimmed.isEmpty) {
      onInsertText(fraction);
    } else {
      // If it ends with a number or symbol without space, add clean space
      if (!currentValue.endsWith(' ')) {
        onInsertText(' $fraction');
      } else {
        onInsertText(fraction);
      }
    }
  }

  void _handleKeyTap(String key) {
    HapticFeedback.lightImpact();
    onInsertText(key);
  }

  void _handleBackspaceTap() {
    HapticFeedback.lightImpact();
    onBackspace();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1F24),
        boxShadow: [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Top Fraction & Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF282A33),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF383A45), width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Active Box Badge with navigation arrows
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            onPrev();
                          },
                          child: const Icon(Icons.chevron_left, color: Colors.white70, size: 18),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'Box $activeBoxNumber',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            onNext();
                          },
                          child: const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Quick Tailor Fractions (1/4, 1/2, 3/4, .5)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['1/4', '1/2', '3/4', '.5'].map((frac) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Material(
                              color: const Color(0xFF3A3D4D),
                              borderRadius: BorderRadius.circular(6),
                              child: InkWell(
                                onTap: () => _handleFractionTap(frac),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF4B4F63)),
                                  ),
                                  child: Text(
                                    frac,
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Clear button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onClear();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Done / Close button
                  Material(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onClose();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.keyboard_hide, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Done',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Custom Keypad Grid (Layout matching website's custom_keypad.js)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
              child: SizedBox(
                height: 200,
                child: Row(
                  children: [
                    // Left Column (Math Operators: +, -, *, /)
                    Container(
                      width: 52,
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF282A33),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildKeyBtn('+', isOperator: true),
                          const SizedBox(height: 4),
                          _buildKeyBtn('-', isOperator: true),
                          const SizedBox(height: 4),
                          _buildKeyBtn('*', isOperator: true),
                          const SizedBox(height: 4),
                          _buildKeyBtn('/', isOperator: true),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Main 4x4 Grid
                    Expanded(
                      child: Column(
                        children: [
                          // Row 1: 1, 2, 3, %
                          Expanded(
                            child: Row(
                              children: [
                                _buildKeyBtn('1'),
                                const SizedBox(width: 6),
                                _buildKeyBtn('2'),
                                const SizedBox(width: 6),
                                _buildKeyBtn('3'),
                                const SizedBox(width: 6),
                                _buildKeyBtn('%', isOperator: true),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),

                          // Row 2: 4, 5, 6, Space
                          Expanded(
                            child: Row(
                              children: [
                                _buildKeyBtn('4'),
                                const SizedBox(width: 6),
                                _buildKeyBtn('5'),
                                const SizedBox(width: 6),
                                _buildKeyBtn('6'),
                                const SizedBox(width: 6),
                                _buildCustomBtn(
                                  onTap: () => _handleKeyTap(' '),
                                  child: const Text('␣', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
                                  bgColor: const Color(0xFF2D303E),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),

                          // Row 3: 7, 8, 9, Backspace
                          Expanded(
                            child: Row(
                              children: [
                                _buildKeyBtn('7'),
                                const SizedBox(width: 6),
                                _buildKeyBtn('8'),
                                const SizedBox(width: 6),
                                _buildKeyBtn('9'),
                                const SizedBox(width: 6),
                                _buildCustomBtn(
                                  onTap: _handleBackspaceTap,
                                  child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 20),
                                  bgColor: const Color(0xFF3F4354),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),

                          // Row 4: 0, =, ., Next (Enter)
                          Expanded(
                            child: Row(
                              children: [
                                _buildKeyBtn('0'),
                                const SizedBox(width: 6),
                                _buildKeyBtn('=', isOperator: true),
                                const SizedBox(width: 6),
                                _buildKeyBtn('.', isOperator: true),
                                const SizedBox(width: 6),
                                _buildCustomBtn(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    onNext();
                                  },
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Next', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                      SizedBox(width: 2),
                                      Icon(Icons.keyboard_return, color: Colors.white, size: 16),
                                    ],
                                  ),
                                  bgColor: const Color(0xFF2563EB),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyBtn(String val, {bool isOperator = false}) {
    return Expanded(
      child: Material(
        color: isOperator ? const Color(0xFF2D303E) : const Color(0xFF353846),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () => _handleKeyTap(val),
          borderRadius: BorderRadius.circular(6),
          splashColor: Colors.white24,
          highlightColor: Colors.white12,
          child: Container(
            alignment: Alignment.center,
            child: Text(
              val,
              style: TextStyle(
                color: isOperator ? const Color(0xFFE2E8F0) : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomBtn({
    required VoidCallback onTap,
    required Widget child,
    required Color bgColor,
  }) {
    return Expanded(
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          splashColor: Colors.white24,
          highlightColor: Colors.white12,
          child: Container(
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
