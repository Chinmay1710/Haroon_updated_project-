import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'custom_measurement_keypad.dart';

class MeasurementGrid extends StatefulWidget {
  final Map<String, TextEditingController>? controllers;
  final Map<String, dynamic>? staticValues;
  final bool isReadOnly;
  final int? activeBoxIndex;
  final ValueChanged<int?>? onBoxSelected;
  final Function(String key, String value)? onChanged;

  const MeasurementGrid({
    super.key,
    this.controllers,
    this.staticValues,
    this.isReadOnly = false,
    this.activeBoxIndex,
    this.onBoxSelected,
    this.onChanged,
  });

  @override
  State<MeasurementGrid> createState() => _MeasurementGridState();
}

class _MeasurementGridState extends State<MeasurementGrid> {
  int? _internalActiveBoxIndex;

  int? get _currentActiveBox => widget.activeBoxIndex ?? _internalActiveBoxIndex;

  void _setActiveBox(int? boxNum) {
    FocusScope.of(context).unfocus(); // Dismiss native keyboard
    if (widget.onBoxSelected != null) {
      widget.onBoxSelected!(boxNum);
    } else {
      setState(() => _internalActiveBoxIndex = boxNum);
    }
  }

  void _insertText(String text) {
    final active = _currentActiveBox;
    if (active == null || widget.controllers == null) return;
    final key = 'Box $active';
    final ctrl = widget.controllers![key];
    if (ctrl == null) return;

    ctrl.text = '${ctrl.text}$text';
    widget.onChanged?.call(key, ctrl.text);
    setState(() {});
  }

  void _handleBackspace() {
    final active = _currentActiveBox;
    if (active == null || widget.controllers == null) return;
    final key = 'Box $active';
    final ctrl = widget.controllers![key];
    if (ctrl == null || ctrl.text.isEmpty) return;

    final val = ctrl.text;
    // Check if ends with fraction
    for (final frac in [' 1/4', ' 1/2', ' 3/4', ' .5', '1/4', '1/2', '3/4', '.5']) {
      if (val.endsWith(frac)) {
        ctrl.text = val.substring(0, val.length - frac.length);
        widget.onChanged?.call(key, ctrl.text);
        setState(() {});
        return;
      }
    }
    ctrl.text = val.substring(0, val.length - 1);
    widget.onChanged?.call(key, ctrl.text);
    setState(() {});
  }

  void _handleClear() {
    final active = _currentActiveBox;
    if (active == null || widget.controllers == null) return;
    final key = 'Box $active';
    final ctrl = widget.controllers![key];
    if (ctrl == null) return;

    ctrl.text = '';
    widget.onChanged?.call(key, '');
    setState(() {});
  }

  void _handleNext() {
    final active = _currentActiveBox;
    if (active == null) return;
    final nextBox = active < 24 ? active + 1 : 1;
    _setActiveBox(nextBox);
  }

  void _handlePrev() {
    final active = _currentActiveBox;
    if (active == null) return;
    final prevBox = active > 1 ? active - 1 : 24;
    _setActiveBox(prevBox);
  }

  @override
  Widget build(BuildContext context) {
    final active = _currentActiveBox;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // 6 Columns x 4 Rows = 24 Boxes (Exact website layout)
        LayoutBuilder(
          builder: (context, constraints) {
            final colWidth = (constraints.maxWidth - (5 * 6)) / 6;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 24,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: colWidth / 48,
              ),
              itemBuilder: (context, index) {
                final boxNum = index + 1;
                final key = 'Box $boxNum';

                if (widget.isReadOnly) {
                  final val = (widget.staticValues?[key] ?? '').toString().trim();
                  final hasValue = val.isNotEmpty;

                  return Container(
                    decoration: BoxDecoration(
                      color: hasValue ? const Color(0xFFEEF2F6) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasValue ? const Color(0xFF0F172A).withValues(alpha: 0.4) : Colors.grey.shade300,
                        width: hasValue ? 1.5 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 2,
                          left: 3,
                          child: Text(
                            '$boxNum',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: hasValue ? const Color(0xFF0F172A) : Colors.grey.shade400,
                            ),
                          ),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              val,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Editable mode
                final ctrl = widget.controllers?[key];
                final val = ctrl?.text ?? '';
                final isSelected = active == boxNum;
                final hasValue = val.trim().isNotEmpty;

                return InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _setActiveBox(boxNum);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEFF6FF)
                          : (hasValue ? const Color(0xFFF8FAFC) : Colors.white),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF2563EB)
                            : (hasValue ? const Color(0xFF64748B) : Colors.grey.shade300),
                        width: isSelected ? 2.5 : (hasValue ? 1.5 : 1.0),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 2,
                          left: 3,
                          child: Text(
                            '$boxNum',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? const Color(0xFF2563EB)
                                  : (hasValue ? const Color(0xFF0F172A) : Colors.grey.shade400),
                            ),
                          ),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    val,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A),
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    width: 1.5,
                                    height: 14,
                                    margin: const EdgeInsets.only(left: 2),
                                    color: const Color(0xFF2563EB),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),

        // Standalone inline keypad if no external parent manages keypad
        if (!widget.isReadOnly && widget.onBoxSelected == null && active != null) ...[
          const SizedBox(height: 12),
          CustomMeasurementKeypad(
            activeBoxNumber: active,
            currentValue: widget.controllers?['Box $active']?.text ?? '',
            onInsertText: _insertText,
            onBackspace: _handleBackspace,
            onClear: _handleClear,
            onNext: _handleNext,
            onPrev: _handlePrev,
            onClose: () => _setActiveBox(null),
          ),
        ],
      ],
    );
  }
}
