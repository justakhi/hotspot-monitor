// Copyright (c) 2026 AP Labs - Akshay Kumar (@justakhi). All rights reserved.
// Licensed under PolyForm Noncommercial License 1.0.0. See LICENSE and NOTICE.

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'data/repositories/hotspot_repository.dart';
import 'data/services/device_alias_service.dart';
import 'data/services/history_store.dart';
import 'data/services/hotspot_platform_service.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/features/dashboard/view_models/dashboard_view_model.dart';
import 'ui/features/dashboard/views/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final platformService = MethodChannelHotspotPlatformService();
  final aliasService = DeviceAliasService();
  final repository = HotspotRepository(
    platformService: platformService,
    aliasService: aliasService,
    historyStore: SqliteHistoryStore(),
  );

  runApp(HotspotMonitorApp(repository: repository));
}

class HotspotMonitorApp extends StatefulWidget {
  const HotspotMonitorApp({super.key, required this.repository});

  final HotspotRepository repository;

  @override
  State<HotspotMonitorApp> createState() => _HotspotMonitorAppState();
}

class _HotspotMonitorAppState extends State<HotspotMonitorApp> {
  late final DashboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel(repository: widget.repository)..initialize();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    widget.repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = AppTheme.light();
    final darkTheme = AppTheme.dark();

    return MaterialApp(
      title: 'Hotspot Monitor',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      theme: ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: lightTheme.colors.background,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: darkTheme.colors.background,
      ),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        final isDark =
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final activeFTheme = isDark ? darkTheme : lightTheme;
        return FTheme(
          data: activeFTheme,
          child: FToaster(child: child ?? const SizedBox.shrink()),
        );
      },
      home: DashboardScreen(viewModel: _viewModel),
    );
  }
}
