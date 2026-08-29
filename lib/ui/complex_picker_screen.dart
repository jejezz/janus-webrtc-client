import 'package:flutter/material.dart';

import '../services/complex_directory.dart';
import '../services/push_service.dart';
import 'theme/app_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/glass.dart';

/// 지역 → 단지 순으로 고른다.
///
/// 앱에는 서버 주소가 들어 있지 않다. 이 화면이 유일하게 아무것도 설정되지 않은
/// 상태에서 동작하며, 고른 단지의 호스트가 이후 모든 주소의 출발점이 된다.
class ComplexPickerScreen extends StatefulWidget {
  const ComplexPickerScreen({super.key});

  @override
  State<ComplexPickerScreen> createState() => _ComplexPickerScreenState();
}

class _ComplexPickerScreenState extends State<ComplexPickerScreen> {
  final ComplexDirectory _directory = const ComplexDirectory();

  List<RegionRef> _regions = const [];
  List<ComplexRef> _complexes = const [];
  RegionRef? _region;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!PushService.isAvailable) {
      // 단지 목록과 푸시는 같은 Firebase 프로젝트를 쓴다. 설정 파일이 없으면
      // 여기서 먼저 막히는데, 원인을 못 짚으면 "목록이 안 나온다" 로만 보인다.
      setState(() {
        _busy = false;
        _error = 'Firebase 설정이 없어 단지 목록을 불러올 수 없습니다.\n'
            'android/app/ 에 google-services.json 을 넣고 다시 실행하세요.';
      });
      return;
    }
    try {
      final regions = await _directory.regions();
      if (!mounted) return;
      setState(() {
        _regions = regions;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _selectRegion(RegionRef region) async {
    setState(() {
      _region = region;
      _busy = true;
      _error = null;
    });
    try {
      final complexes = await _directory.complexes(region.code);
      if (!mounted) return;
      setState(() {
        _complexes = complexes;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  void _back() {
    setState(() {
      _region = null;
      _complexes = const [];
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final region = _region;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(region == null ? '지역 선택' : region.name),
        leading: region == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
      ),
      body: AuroraBackground(
        child: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_busy) return const Center(child: CircularProgressIndicator());

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppPalette.danger),
              const SizedBox(height: 16),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  final region = _region;
                  region == null ? _loadRegions() : _selectRegion(region);
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('다시 시도'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_region == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const Text(
            '어느 단지에 사시나요?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            '지역을 고르면 그 지역의 단지 목록이 나옵니다.',
            style: TextStyle(fontSize: 13, color: Colors.white54),
          ),
          const SizedBox(height: 20),
          for (final region in _regions) ...[
            _PickerTile(
              icon: Icons.map_outlined,
              title: region.name,
              subtitle: region.code,
              onTap: () => _selectRegion(region),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        for (final complex in _complexes) ...[
          _PickerTile(
            icon: Icons.apartment_outlined,
            title: complex.name,
            // 단지를 고르는 데 서버 주소 전체가 필요하지는 않다.
            subtitle: complex.maskedHost,
            onTap: () => Navigator.of(context).pop(complex),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      radius: 20,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: AppPalette.cyan, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
