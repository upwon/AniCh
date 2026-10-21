import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NavItem {
  const NavItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String title;
  final bool selected;
}

class NavBar extends StatefulWidget {
  const NavBar({super.key, required this.children});
  final List<NavItem> children;

  @override
  State<NavBar> createState() => _NavBar();
}

class _NavBar extends State<NavBar> {
  @override
  Widget build(BuildContext context) {
    return _navBar();
  }

  Widget _navBar() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          width: math.min(MediaQuery.sizeOf(context).width - 32, 420),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          margin: const EdgeInsets.only(top: 20, right: 16, left: 16, bottom: 22),
          decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                    blurRadius: 20,
                    color: Colors.black.withAlpha(10),
                    spreadRadius: 10)
              ]),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: widget.children.map((item) {
              final color = item.selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey;
              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: item.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.icon, color: color),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: color, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        )
      ],
    );
  }
}

class AppMainNavBar extends StatelessWidget {
  const AppMainNavBar({super.key, required this.selectedRoute});

  final String selectedRoute;

  void _navigate(String route) {
    if (Get.currentRoute != route) Get.offAllNamed(route);
  }

  @override
  Widget build(BuildContext context) => NavBar(children: [
        NavItem(
          icon: Icons.photo_library_outlined,
          title: '图片',
          selected: selectedRoute == '/',
          onTap: () => _navigate('/'),
        ),
        NavItem(
          icon: Icons.movie_outlined,
          title: '番剧',
          selected: selectedRoute == '/bangumi',
          onTap: () => _navigate('/bangumi'),
        ),
        NavItem(
          icon: Icons.download_for_offline_outlined,
          title: '缓存',
          selected: selectedRoute == '/download',
          onTap: () => _navigate('/download'),
        ),
        NavItem(
          icon: Icons.history,
          title: '历史',
          selected: selectedRoute == '/play_history',
          onTap: () => _navigate('/play_history'),
        ),
        NavItem(
          icon: Icons.person_outline,
          title: '我的',
          selected: selectedRoute == '/profile',
          onTap: () => _navigate('/profile'),
        ),
      ]);
}
