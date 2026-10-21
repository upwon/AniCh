import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xs/src/pages/search_panel/controller.dart';
import 'package:xs/src/widgets/drag_to_move_bar.dart';

class SearchPanelPage extends StatefulWidget {
  const SearchPanelPage({super.key});

  @override
  State<SearchPanelPage> createState() => _SearchPanelPageState();
  static final RouteObserver<PageRoute> routeObserver =
      RouteObserver<PageRoute>();
}

class _SearchPanelPageState extends State<SearchPanelPage> with RouteAware {
  final SearchPanelController _searchController =
      Get.put(SearchPanelController());

  @override
  void initState() {
    super.initState();
  }

  @override
  // 返回当前页面时
  void didPopNext() async {
    _searchController.searchFocusNode.requestFocus();
    super.didPopNext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SearchPanelPage.routeObserver
        .subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: CustomDragToMoveArea(
              child: AppBar(
            shape: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.08),
                width: 1,
              ),
            ),
            titleSpacing: 0,
            leading: IconButton(
              onPressed: () {
                Get.back();
              },
              icon: const Icon(
                Icons.arrow_back,
                size: 22,
              ),
            ),
            actions: [
              IconButton(
                onPressed: () => _searchController.submit(),
                icon: const Icon(Icons.search, size: 22),
              ),
              const SizedBox(width: 10)
            ],
            title: Obx(
              () => TextField(
                autofocus: true,
                focusNode: _searchController.searchFocusNode,
                controller: _searchController.controller.value,
                textAlignVertical: TextAlignVertical.center,
                textInputAction: TextInputAction.search,
                style: const TextStyle(textBaseline: TextBaseline.alphabetic),
                onChanged: (value) => _searchController.onChange(value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _searchController.hintText,
                  hintStyle:
                      const TextStyle(textBaseline: TextBaseline.alphabetic),
                  border: InputBorder.none,
                  // contentPadding: const EdgeInsets.only(top: 10),
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.clear,
                      size: 22,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    onPressed: () => _searchController.onClear(),
                  ),
                ),
                onSubmitted: (String value) => _searchController.submit(),
              ),
            ),
          ))),
      body: Obx(() {
        final history = _searchController.historyList;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('最近搜索',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (history.isNotEmpty)
                  TextButton.icon(
                    onPressed: _searchController.clearHistory,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空'),
                  ),
              ],
            ),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  '搜索记录保存在本机，登录与否都可以使用。',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final keyword in history.cast<String>())
                    InputChip(
                      label: Text(keyword),
                      onPressed: () =>
                          _searchController.onClickKeyword(keyword),
                      onDeleted: () =>
                          _searchController.removeHistory(keyword),
                    ),
                ],
              ),
          ],
        );
      }),
    );
  }
}
