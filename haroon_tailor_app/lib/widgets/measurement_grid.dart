import 'package:flutter/material.dart';

class MeasurementGrid extends StatefulWidget {
  final Map<String, TextEditingController>? controllers;
  final Map<String, dynamic>? staticValues;
  final bool isReadOnly;
  final Function(String key, String value)? onChanged;

  const MeasurementGrid({
    super.key,
    this.controllers,
    this.staticValues,
    this.isReadOnly = false,
    this.onChanged,
  });

  @override
  State<MeasurementGrid> createState() => _MeasurementGridState();
}

class _MeasurementGridState extends State<MeasurementGrid> {
  int? _activeBoxIndex;

  void _insertFraction(String fraction) {
    if (_activeBoxIndex == null || widget.controllers == null) return;
    final key = 'Box $_activeBoxIndex';
    final ctrl = widget.controllers![key];
    if (ctrl == null) return;

    final curText = ctrl.text.trim();
    if (curText.isEmpty) {
      ctrl.text = fraction;
    } else {
      ctrl.text = '$curText $fraction';
    }
    widget.onChanged?.call(key, ctrl.text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick fraction helper toolbar for mobile tailors when editing
        if (!widget.isReadOnly) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Text(
                  _activeBoxIndex != null ? 'Box $_activeBoxIndex:' : 'Tap box & tap:',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['1/4', '1/2', '3/4', '.5'].map((f) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => _insertFraction(f),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF0F172A).withOpacity(0.3)),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
                                ],
                              ),
                              child: Text(
                                f,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

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
                        color: hasValue ? const Color(0xFF0F172A).withOpacity(0.4) : Colors.grey.shade300,
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
                final isSelected = _activeBoxIndex == boxNum;

                return Focus(
                  onFocusChange: (hasFocus) {
                    if (hasFocus) {
                      setState(() => _activeBoxIndex = boxNum);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF0F172A) : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.15), blurRadius: 4)]
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
                              color: isSelected ? const Color(0xFF0F172A) : Colors.grey.shade400,
                            ),
                          ),
                        ),
                        TextField(
                          controller: ctrl,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.text,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.only(top: 8, bottom: 2, left: 2, right: 2),
                            isDense: true,
                          ),
                          onTap: () {
                            setState(() => _activeBoxIndex = boxNum);
                          },
                          onChanged: (v) => widget.onChanged?.call(key, v),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
