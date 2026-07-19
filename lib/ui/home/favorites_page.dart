import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../state/app_state.dart';
import '../common/widgets.dart';
import '../record/record_detail_page.dart';
import '../timeline/record_card.dart';

/// 我的收藏：所有标记了喜欢的记录。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Moment> _items = [];
  bool _loading = true;
  int _loadedVersion = -1;
  String? _loadedBabyId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (state.version != _loadedVersion ||
        state.currentBaby?.id != _loadedBabyId) {
      _loadedVersion = state.version;
      _loadedBabyId = state.currentBaby?.id;
      _load();
    }
  }

  Future<void> _load() async {
    final baby = context.read<AppState>().currentBaby;
    if (baby == null) return;
    final items = await MomentRepository().query(baby.id,
        filter: const MomentFilter(favoriteOnly: true), limit: 200);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baby = context.watch<AppState>().currentBaby;
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? const EmptyView(
                  icon: Icons.favorite_border_rounded,
                  title: '还没有收藏',
                  message: '在记录详情页点击心形，把最珍贵的瞬间收藏起来',
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 60),
                  children: [
                    for (final m in _items)
                      RecordCard(
                        moment: m,
                        baby: baby,
                        heroTag: 'fav_${m.id}',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => RecordDetailPage(
                                  momentId: m.id,
                                  heroTag: 'fav_${m.id}')),
                        ),
                      ),
                  ],
                ),
    );
  }
}
