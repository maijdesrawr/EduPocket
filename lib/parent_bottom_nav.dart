import 'package:flutter/material.dart';

class ParentBottomNav extends StatelessWidget {
  static const Color _primaryRed = Color(0xFFC62828);
  static const Color _deepRed = Color(0xFFB71C1C);

  final int selectedIndex;
  final ValueChanged<int> onTap;

  const ParentBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: _primaryRed,
        child: Container(
          height: 92,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(46),
              topRight: Radius.circular(46),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded),
              _buildNavItem(1, Icons.payments_outlined),
              _buildNavItem(2, Icons.history_rounded),
              _buildNavItem(3, Icons.person_outline_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final selected = selectedIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: selected ? _deepRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          size: 28,
          color: selected ? Colors.white : _primaryRed,
        ),
      ),
    );
  }
}
