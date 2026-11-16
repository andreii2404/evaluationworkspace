import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../services/cloud_repository.dart';
import '../services/questionnaire_data.dart';
import '../widgets/app_notice.dart';
import '../widgets/cantiere_wordmark.dart';
import '../widgets/evaluation_backdrop.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/workshop_glass.dart';
import '../widgets/workspace_select.dart';
import 'account_setup_screen.dart';
import 'account_security_screen.dart';
import 'community_screen.dart';
import 'community_workflows.dart';
import 'questionnaire_editor.dart';
import 'workspace_files_screen.dart';
import 'workspace_forms.dart';
import 'workspace_practice_guide.dart';
import 'workspace_walkthrough.dart';

enum _ReviewFilter {
  all('All reviews'),
  awaiting('Awaiting feedback'),
  received('Feedback received'),
  assigned('Reviews to do');

  const _ReviewFilter(this.label);
  final String label;
}

enum _Area {
  overview('Overview', Icons.grid_view_rounded),
  community('Community', Icons.hub_outlined),
  projects('Projects', Icons.layers_outlined),
  questionnaires('Questionnaires', Icons.fact_check_outlined),
  directory('Evaluators', Icons.group_outlined),
  reviews('Reviews', Icons.rate_review_outlined),
  files('Files', Icons.folder_outlined),
  profile('Profile', Icons.person_outline_rounded),
  moderation('Moderation', Icons.shield_outlined);

  const _Area(this.title, this.icon);
  final String title;
  final IconData icon;
}

class CloudWorkspace extends StatelessWidget {
  const CloudWorkspace({super.key, required this.client, required this.userId});
  final SupabaseClient client;
  final String userId;

  @override
  Widget build(BuildContext context) => Theme(
    data: workshopTheme(Theme.of(context)),
    child: _AccountGate(client: client, userId: userId),
  );
}

class _AccountGate extends StatefulWidget {
  const _AccountGate({required this.client, required this.userId});

  final SupabaseClient client;
  final String userId;

  @override
  State<_AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<_AccountGate> {
  late final _repo = CloudRepository(widget.client, widget.userId);
  late Future<WorkspaceRow> _profile = _checkSession(_repo.loadProfile);
  WorkspaceRow? _completedProfile;

  Future<void> _backToSignIn({bool ended = false}) async {
    final auth = widget.client.auth;
    if (!mounted || auth.currentUser?.id != widget.userId) return;
    Navigator.of(context).popUntil((route) => route is! PopupRoute);
    if (ended) {
      AppNotice.show(
        context,
        workspaceSessionEndedMessage,
        tone: NoticeTone.info,
      );
    }
    try {
      await auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      if (!mounted) return;
      if (auth.currentUser == null) {
        Navigator.of(context).pushReplacementNamed('/login');
      } else if (auth.currentUser?.id == widget.userId) {
        AppNotice.show(
          context,
          'Couldn’t sign out. Please try again.',
          tone: NoticeTone.error,
        );
      }
    }
  }

  Future<T> _checkSession<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      if (workspaceSessionEnded(error)) await _backToSignIn(ended: true);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WorkspaceRow>(
    future: _profile,
    builder: (context, snapshot) {
      if (snapshot.hasError &&
          snapshot.connectionState == ConnectionState.done) {
        return AccountSetupFrame(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppNotice(
                workspaceSessionEnded(snapshot.error)
                    ? workspaceSessionEndedMessage
                    : 'Couldn’t load your profile. Check your connection or try signing in again.',
                tone: NoticeTone.error,
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () {
                      final profile = _checkSession(_repo.loadProfile);
                      setState(() {
                        _profile = profile;
                      });
                    },
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: _backToSignIn,
                    child: const Text('Back to sign in'),
                  ),
                ],
              ),
            ],
          ),
        );
      }
      final profile = _completedProfile ?? snapshot.data;
      if (profile == null) {
        return const AccountSetupFrame(
          child: SkeletonRows(label: 'Loading profile', leading: true),
        );
      }
      if (profile['onboarding_completed'] == true) {
        return _Workspace(
          client: widget.client,
          userId: widget.userId,
          initialProfile: profile,
          onSessionEnded: () => _backToSignIn(ended: true),
        );
      }
      return AccountSetupScreen(
        profile: profile,
        save: (values) async {
          final updated = await _checkSession(
            () => _repo.completeOnboarding(values),
          );
          if (updated['onboarding_completed'] != true) {
            throw StateError('Account setup was not saved');
          }
          if (mounted) setState(() => _completedProfile = updated);
        },
        signOut: _backToSignIn,
      );
    },
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({
    required this.client,
    required this.userId,
    required this.initialProfile,
    required this.onSessionEnded,
  });
  final SupabaseClient client;
  final String userId;
  final WorkspaceRow initialProfile;
  final Future<void> Function() onSessionEnded;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  late final _repo = CloudRepository(widget.client, widget.userId);
  late Future<WorkspaceData> _data = _load(
    initialProfile: widget.initialProfile,
  );
  late Future<List<QuestionnaireChoice>> _savedQuestionnaires = _repo
      .savedQuestionnaires();
  final _workspaceBackdrop = BackdropKey();
  final _updatesMenu = MenuController();
  final _updatesFocus = FocusNode();
  RealtimeChannel? _updates;
  _Area _area = _Area.overview;
  bool _busy = false;
  bool _railHovered = false, _railFocused = false, _railPinned = false;
  bool _community = false;
  String _query = '';
  String? _evaluatorType;
  String? _briefProjectId;
  _ReviewFilter _reviewFilter = _ReviewFilter.all;
  late WalkthroughStep? _tourStep =
      widget.initialProfile['walkthrough_finished'] == false
      ? WalkthroughStep.overview
      : null;
  final _tourViewport = GlobalKey();
  final _tourTarget = GlobalKey();
  Rect? _tourBounds;
  bool _tourPreviewOpen = false;
  WorkspaceRow? _tourDraft;
  ReviewDraft? _tourReview;
  bool _tourShared = false;
  bool _savingTour = false;
  bool _replayingTour = false;
  String? _tourError;

  @override
  void initState() {
    super.initState();
    _updates = widget.client
        .channel('evalink-reviews-${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'review_assignments',
          callback: (_) => _refresh(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _updatesFocus.dispose();
    final channel = _updates;
    if (channel != null) widget.client.removeChannel(channel);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final data = _load();
    setState(() {
      _data = data;
    });
  }

  Future<WorkspaceData> _load({WorkspaceRow? initialProfile}) async {
    try {
      return await _repo.load(initialProfile: initialProfile);
    } catch (error) {
      if (mounted && workspaceSessionEnded(error)) {
        await widget.onSessionEnded();
      }
      rethrow;
    }
  }

  void _notice(String message, {NoticeTone tone = NoticeTone.success}) =>
      AppNotice.show(context, message, tone: tone);

  Future<void> _change(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _refresh();
      _notice(done);
    } catch (error) {
      if (mounted && workspaceSessionEnded(error)) {
        await widget.onSessionEnded();
      } else if (mounted) {
        _notice(workspaceError(error), tone: NoticeTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(_Area area, {_ReviewFilter reviews = _ReviewFilter.all}) =>
      setState(() {
        _area = area;
        _reviewFilter = reviews;
        _query = '';
      });

  void _showTourStep(WalkthroughStep step) {
    setState(() {
      _tourStep = step;
      _tourBounds = null;
      _tourError = null;
      _community = step == WalkthroughStep.evaluate;
      _area = switch (step) {
        WalkthroughStep.overview => _Area.overview,
        WalkthroughStep.templates => _Area.questionnaires,
        _ => _Area.projects,
      };
      _query = '';
    });
  }

  void _measureTourTarget() {
    final step = _tourStep;
    if (step == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tourStep != step) return;
      final viewport = _tourViewport.currentContext?.findRenderObject();
      final target = _tourTarget.currentContext?.findRenderObject();
      final bounds =
          viewport is RenderBox &&
              viewport.hasSize &&
              target is RenderBox &&
              target.hasSize
          ? target.localToGlobal(Offset.zero, ancestor: viewport) & target.size
          : null;
      if (bounds != _tourBounds) setState(() => _tourBounds = bounds);
    });
  }

  void _closeTour() => setState(() {
    _tourStep = null;
    _tourBounds = null;
    _tourDraft = null;
    _tourReview = null;
    _tourShared = false;
  });

  Future<void> _tryTourControl() async {
    final step = _tourStep;
    if (_tourPreviewOpen || step == null || step == WalkthroughStep.overview) {
      return;
    }
    _tourPreviewOpen = true;
    try {
      final completed = await switch (step) {
        WalkthroughStep.create => _createPracticeProject(),
        WalkthroughStep.publish => _sharePracticeProject(),
        WalkthroughStep.evaluate => _evaluatePracticeProject(),
        WalkthroughStep.results => _viewPracticeResponses(),
        WalkthroughStep.templates => _previewTourTemplate(),
        WalkthroughStep.overview => Future.value(false),
      };
      if (completed &&
          mounted &&
          _tourStep == step &&
          step != WalkthroughStep.values.last) {
        _showTourStep(WalkthroughStep.values[step.index + 1]);
      }
    } finally {
      _tourPreviewOpen = false;
    }
  }

  Future<void> _finishTour() async {
    if (_savingTour) return;
    if (_replayingTour) {
      _closeTour();
      return;
    }
    setState(() {
      _savingTour = true;
      _tourError = null;
    });
    try {
      await _repo.finishWalkthrough();
      if (mounted) _closeTour();
    } catch (error) {
      if (mounted) setState(() => _tourError = workspaceError(error));
    } finally {
      if (mounted) setState(() => _savingTour = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 960;
      _measureTourTarget();
      return Scaffold(
        backgroundColor: workshopNight,
        drawer: wide
            ? null
            : Drawer(
                backgroundColor: workshopSurface,
                surfaceTintColor: Colors.transparent,
                child: SafeArea(
                  child: _navigation(drawer: true, expanded: true),
                ),
              ),
        body: Stack(
          key: _tourViewport,
          fit: StackFit.expand,
          children: [
            const EvaluationBackdrop(),
            ExcludeFocus(
              excluding: _tourStep != null,
              child: ExcludeSemantics(
                excluding: _tourStep != null,
                child: BackdropGroup(
                  backdropKey: _workspaceBackdrop,
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: Padding(
                          padding: EdgeInsets.all(wide ? 24 : 12),
                          child: Column(
                            children: [
                              _toolbar(wide),
                              SizedBox(height: wide ? 16 : 10),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (wide) ...[
                                      _desktopRail(),
                                      const SizedBox(width: 16),
                                    ],
                                    Expanded(child: _content(wide)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_tourStep case final step?)
              WorkspaceWalkthrough(
                step: step,
                target: _tourBounds,
                busy: _savingTour,
                error: _tourError,
                tryControl: step.action == null ? null : _tryTourControl,
                back: step.index == 0
                    ? null
                    : () =>
                          _showTourStep(WalkthroughStep.values[step.index - 1]),
                next: step == WalkthroughStep.values.last
                    ? _finishTour
                    : () =>
                          _showTourStep(WalkthroughStep.values[step.index + 1]),
                skip: _finishTour,
              ),
          ],
        ),
      );
    },
  );

  Widget _toolbar(bool wide) => WorkshopGlass(
    radius: 28,
    featured: true,
    child: Padding(
      padding: EdgeInsets.fromLTRB(wide ? 18 : 5, 7, 8, 7),
      child: Row(
        children: [
          if (!wide)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Open workspace menu',
                icon: const Icon(Icons.menu_rounded),
                onPressed: Scaffold.of(context).openDrawer,
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => CantiereWordmark(
                fontSize: 24,
                iconOnly: constraints.maxWidth < 108,
              ),
            ),
          ),
          if (wide) ...[
            const Text(
              'Personal workspace',
              style: TextStyle(color: workshopMuted),
            ),
            const SizedBox(width: 16),
          ],
          IconButton(
            tooltip: 'Refresh workspace',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          _updatesButton(),
          IconButton(
            tooltip: 'Open profile',
            isSelected: _area == _Area.profile,
            onPressed: () => _select(_Area.profile),
            icon: const Icon(Icons.account_circle_outlined, size: 23),
            selectedIcon: const Icon(Icons.account_circle, size: 23),
          ),
        ],
      ),
    ),
  );

  Widget _updatesButton() {
    final viewport = MediaQuery.sizeOf(context);
    final width = (viewport.width - 24).clamp(0.0, 368.0);
    return MenuAnchor(
      controller: _updatesMenu,
      childFocusNode: _updatesFocus,
      alignmentOffset: Offset(96 - width, 12),
      reservedPadding: const EdgeInsets.all(12),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(workshopSurface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: const BorderSide(color: workshopEdge),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (viewport.height * .65).clamp(0.0, 440.0),
            ),
            child: WorkspaceUpdates(
              repository: _repo,
              close: _updatesMenu.close,
              open: (row) {
                _updatesMenu.close();
                _openUpdate(row);
              },
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => IconButton(
        focusNode: _updatesFocus,
        tooltip: 'Updates',
        isSelected: controller.isOpen,
        icon: const Icon(Icons.notifications_none_rounded, size: 22),
        selectedIcon: const Icon(Icons.notifications_rounded, size: 22),
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
    );
  }

  Future<void> _openUpdate(WorkspaceRow row) async {
    if (row['kind'] == 'team') {
      _refresh();
      _select(_Area.projects);
      return;
    }
    if (row['kind'] == 'message') {
      try {
        var data = await _data;
        if (!mounted) return;
        final id = row['assignment_id'];
        if (!data.assignments.any((assignment) => assignment['id'] == id)) {
          _refresh();
          data = await _data;
          if (!mounted) return;
        }
        final assignment = data.assignments
            .where((item) => item['id'] == id)
            .firstOrNull;
        if (assignment != null && assignment['status'] != 'declined') {
          showReviewConversation(context, _repo, assignment);
          return;
        }
        _notice(
          'This review conversation is no longer available.',
          tone: NoticeTone.info,
        );
      } catch (error) {
        if (mounted) _notice(workspaceError(error), tone: NoticeTone.error);
      }
      return;
    }
    _refresh();
    _select(_Area.reviews);
  }

  Widget _desktopRail() {
    final expanded = _railHovered || _railFocused || _railPinned;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 210);
    return MouseRegion(
      onEnter: (_) => setState(() => _railHovered = true),
      onExit: (_) => setState(() => _railHovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) => setState(() => _railFocused = focused),
        child: AnimatedContainer(
          width: expanded ? 206 : 62,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: WorkshopGlass(
            child: _navigation(drawer: false, expanded: expanded),
          ),
        ),
      ),
    );
  }

  Widget _navigation({required bool drawer, required bool expanded}) {
    final areas = _Area.values.where(
      (area) =>
          area != _Area.profile &&
          (area != _Area.moderation || _repo.isModerator),
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    Widget item(
      String label,
      IconData icon,
      VoidCallback? onTap, {
      bool selected = false,
    }) => Semantics(
      label: label,
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0x405E82B4) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: ExcludeSemantics(
            child: SizedBox(
              height: 43,
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Icon(
                      icon,
                      size: 20,
                      color: selected ? workshopIce : workshopMuted,
                    ),
                  ),
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: expanded ? 1 : 0,
                      duration: duration,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          color: selected ? workshopText : workshopMuted,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (drawer)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 15, 8, 12),
              child: _Kicker('WORKSPACE'),
            )
          else
            item(
              _railPinned ? 'Unpin sidebar' : 'Pin sidebar',
              _railPinned ? Icons.push_pin : Icons.menu_open_rounded,
              () => setState(() => _railPinned = !_railPinned),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final area in areas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: item(area.title, area.icon, () {
                      if (drawer) Navigator.pop(context);
                      _select(area);
                    }, selected: _area == area),
                  ),
              ],
            ),
          ),
          const Divider(height: 12),
          item(
            'Sign out',
            Icons.logout,
            _busy
                ? null
                : () async {
                    try {
                      await widget.client.auth.signOut();
                    } catch (error) {
                      if (mounted) {
                        _notice(workspaceError(error), tone: NoticeTone.error);
                      }
                    }
                  },
          ),
        ],
      ),
    );
  }

  Widget _content(bool wide) => FutureBuilder<WorkspaceData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _Blank(
          icon: Icons.cloud_off_outlined,
          title: 'Couldn’t load your workspace',
          action: TextButton(
            onPressed: _refresh,
            child: const Text('Try again'),
          ),
        );
      }
      final data = snapshot.data;
      if (data == null) {
        return const _WorkspaceLoading();
      }
      _measureTourTarget();
      final reduceMotion =
          _tourStep != null || MediaQuery.disableAnimationsOf(context);
      return Column(
        children: [
          if (_busy || snapshot.connectionState == ConnectionState.waiting)
            const LoadingSkeleton(
              label: 'Refreshing workspace',
              child: SkeletonBlock(height: 3, width: double.infinity),
            )
          else
            const SizedBox(height: 2),
          Expanded(
            child: SingleChildScrollView(
              key: _tourStep == null
                  ? PageStorageKey(_area)
                  : ValueKey(_tourStep),
              padding: EdgeInsets.fromLTRB(wide ? 2 : 0, wide ? 8 : 4, 2, 20),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_area),
                tween: Tween(begin: 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => value == 1
                    ? child!
                    : Transform.translate(
                        offset: Offset(0, 8 * (1 - value)),
                        child: child,
                      ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_area != _Area.overview) ...[
                          Semantics(
                            header: true,
                            child: Text(
                              _area.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        switch (_area) {
                          _Area.overview => _overview(data),
                          _Area.community => CommunityScreen(
                            repository: _repo,
                            profile: data.profile,
                            directory: data.directory,
                            openProfile: (member) =>
                                _showEvaluator(member, data),
                            editVisibility: () => _select(_Area.profile),
                            openProjects: () {
                              _community = true;
                              _select(_Area.projects);
                            },
                            onSessionEnded: widget.onSessionEnded,
                          ),
                          _Area.projects => _projects(data),
                          _Area.questionnaires => _questionnaireLibrary(),
                          _Area.directory => _directory(data),
                          _Area.reviews => _reviews(data),
                          _Area.files => WorkspaceFilesScreen(
                            repository: _repo,
                          ),
                          _Area.profile => _profile(data),
                          _Area.moderation => _moderation(data),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  void _showMyProjects() {
    _community = false;
    _select(_Area.projects);
  }

  bool _isOpenReview(WorkspaceRow row) =>
      row['status'] == 'invited' || row['status'] == 'accepted';

  Widget _overview(WorkspaceData data) {
    final requests = data.assignments.where(
      (row) => row['evaluator_id'] != widget.userId,
    );
    final awaiting = requests.where(_isOpenReview);
    final received = requests.where((row) => row['status'] == 'submitted');
    final assigned = data.assignments.where(
      (row) => row['evaluator_id'] == widget.userId && _isOpenReview(row),
    );
    final name = (data.profile['display_name'] as String?)?.trim() ?? '';
    final welcome = name.isEmpty ? 'Your workspace' : 'Welcome, $name.';
    final metrics = [
      _Metric(
        'My projects',
        data.projects.length,
        Icons.layers_outlined,
        _showMyProjects,
      ),
      _Metric(
        'Awaiting feedback',
        awaiting.length,
        Icons.schedule,
        () => _select(_Area.reviews, reviews: _ReviewFilter.awaiting),
      ),
      _Metric(
        'Feedback received',
        received.length,
        Icons.rate_review_outlined,
        () => _select(_Area.reviews, reviews: _ReviewFilter.received),
      ),
      _Metric(
        'Reviews to do',
        assigned.length,
        Icons.task_alt_outlined,
        () => _select(_Area.reviews, reviews: _ReviewFilter.assigned),
      ),
    ];
    final activity = [
      ?assigned.firstOrNull,
      ?received.firstOrNull,
      ?awaiting.firstOrNull,
    ];
    final projectsPanel = _overviewPanel(
      'Recent projects',
      action: data.projects.isEmpty
          ? null
          : TextButton(
              onPressed: _showMyProjects,
              child: const Text('View all projects'),
            ),
      children: [
        if (data.projects.isEmpty)
          _overviewNote('Add a project to start requesting feedback.')
        else
          for (final project in data.projects.take(3))
            _projectOverviewRow(project, requests),
      ],
    );
    final activityPanel = _overviewPanel(
      'Review activity',
      action: activity.isEmpty
          ? null
          : TextButton(
              onPressed: () => _select(_Area.reviews),
              child: const Text('All reviews'),
            ),
      children: [
        if (activity.isEmpty)
          _overviewNote(
            'Review requests, invitations, and feedback will appear here.',
          )
        else
          for (final assignment in activity)
            _activityOverviewRow(assignment, data),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Kicker('OVERVIEW'),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: Text(
                    welcome,
                    key: _tourStep == WalkthroughStep.overview
                        ? _tourTarget
                        : null,
                    style: const TextStyle(
                      fontFamily: 'Instrument Serif',
                      color: workshopText,
                      fontSize: 30,
                      height: 1.04,
                      letterSpacing: .12,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Track your projects, feedback, and reviews you’re invited to.',
                  style: TextStyle(color: workshopMuted),
                ),
              ],
            ),
            WorkshopAction(
              onPressed: _busy ? null : _createProject,
              icon: Icons.add,
              label: 'New project',
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, bounds) {
            final columns = bounds.maxWidth >= 760 ? 4 : 2;
            const gap = 10.0;
            final width = (bounds.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 2,
              children: [
                for (final metric in metrics)
                  SizedBox(width: width, child: metric),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, bounds) => bounds.maxWidth >= 730
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: projectsPanel),
                    const SizedBox(width: 14),
                    Expanded(child: activityPanel),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [projectsPanel, activityPanel],
                ),
        ),
        if (data.projects.isNotEmpty) ...[
          const SizedBox(height: 6),
          _reviewKit(data.projects),
        ],
      ],
    );
  }

  Widget _reviewKit(List<WorkspaceRow> projects) {
    final project =
        projects.where((row) => row['id'] == _briefProjectId).firstOrNull ??
        projects.first;
    final link = (project['artifact_url'] as String?)?.trim();
    final hasLink = link != null && link.isNotEmpty;
    final hasChecklist = hasQuestionnaire(project);
    final private = project['visibility'] == 'private';
    final picker = WorkspaceSelect<String>(
      key: ValueKey(project['id']),
      label: 'Project for review kit',
      initial: project['id'] as String,
      choices: {
        for (final row in projects) row['id'] as String: row['title'] as String,
      },
      onChanged: (id) => setState(() => _briefProjectId = id),
    );
    return WorkshopGlass(
      featured: true,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: LayoutBuilder(
          builder: (context, bounds) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Kicker('FIELD TOOLS'),
                      const SizedBox(height: 4),
                      Semantics(
                        header: true,
                        child: const Text(
                          'Review kit',
                          style: TextStyle(
                            fontFamily: 'Instrument Serif',
                            fontSize: 23,
                            height: 1.1,
                            color: workshopText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Copy your brief, project link, and feedback prompts.',
                        style: TextStyle(fontSize: 11, color: workshopMuted),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: bounds.maxWidth >= 645 ? 250 : bounds.maxWidth,
                    child: picker,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _KitTag(
                        private ? Icons.lock_outline : Icons.group_outlined,
                        private ? 'Private' : 'Community',
                      ),
                      _KitTag(
                        hasLink ? Icons.link : Icons.info_outline,
                        hasLink ? 'Link attached' : 'Link missing',
                        attention: !hasLink,
                      ),
                      _KitTag(
                        hasChecklist ? Icons.checklist : Icons.info_outline,
                        hasChecklist
                            ? 'Questionnaire ready'
                            : 'Questionnaire missing',
                        attention: !hasChecklist,
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copyReviewBrief(project, link),
                    icon: const Icon(Icons.copy_outlined, size: 15),
                    label: const Text('Copy review brief'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyReviewBrief(WorkspaceRow project, String? link) async {
    final text = [
      project['title'] as String,
      '',
      project['summary'] as String,
      if (link != null && link.isNotEmpty) ...['', 'Project link: $link'],
      if (project['test_instructions'] case final String instructions) ...[
        '',
        'What to try:',
        instructions,
      ],
      if (project['questionnaire_url'] case final String url) ...[
        '',
        'Questionnaire: $url',
      ],
      if (project['questionnaire_file_name'] case final String name) ...[
        '',
        'Questionnaire file in In Cantiere: $name',
      ],
      if (projectQuestionnaire(project) case final form?) ...[
        '',
        'Questionnaire in In Cantiere: ${form.title}',
      ],
      '',
      'Please try the project and share your feedback.',
      '• What worked well?',
      '• Where did you get stuck?',
      '• What would you change first?',
    ].join('\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _notice('Review brief copied');
    } on PlatformException {
      if (mounted) {
        _notice('Couldn’t copy the review brief', tone: NoticeTone.error);
      }
    }
  }

  Widget _overviewPanel(
    String title, {
    Widget? action,
    required List<Widget> children,
  }) => _Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 6, 7, 6),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (action != null) action else const SizedBox(height: 40),
            ],
          ),
        ),
        for (final row in children) ...[
          const Divider(height: 1, indent: 15, endIndent: 15),
          row,
        ],
      ],
    ),
  );

  Widget _overviewNote(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(15, 13, 15, 16),
    child: Text(message, style: const TextStyle(color: workshopMuted)),
  );

  Widget _projectOverviewRow(
    WorkspaceRow project,
    Iterable<WorkspaceRow> requests,
  ) {
    final related = requests.where((row) => row['project_id'] == project['id']);
    final open = related.where(_isOpenReview).length;
    final finished = related
        .where((row) => row['status'] == 'submitted')
        .length;
    return ListTile(
      leading: Icon(
        project['visibility'] == 'private'
            ? Icons.lock_outline
            : Icons.layers_outlined,
        size: 19,
      ),
      title: Text(project['title'] as String),
      titleTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: workshopText,
      ),
      subtitleTextStyle: const TextStyle(fontSize: 11, color: workshopMuted),
      subtitle: Text(
        [
          project['category'],
          if (open > 0) '$open pending',
          if (finished > 0) '$finished completed',
          if (open == 0 && finished == 0) 'No active reviews',
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: () => _showProject(project, team: true),
    );
  }

  Widget _activityOverviewRow(WorkspaceRow row, WorkspaceData data) {
    final incoming = row['evaluator_id'] == widget.userId;
    final project = row['projects'] as WorkspaceRow?;
    final (label, icon, tone) = switch ((incoming, row['status'])) {
      (true, 'invited') => (
        'Invitation to review',
        Icons.mark_email_unread_outlined,
        const Color(0xFFFFD99D),
      ),
      (true, _) => (
        'Ready for your review',
        Icons.task_alt_outlined,
        workshopIce,
      ),
      (_, 'submitted') => (
        'Feedback received',
        Icons.check_circle_outline,
        const Color(0xFFB6F3D8),
      ),
      (_, 'accepted') => ('In review', Icons.rate_review_outlined, workshopIce),
      _ => ('Awaiting a reply', Icons.schedule, const Color(0xFFFFD99D)),
    };
    final reviewer =
        (row['evaluator'] as WorkspaceRow?)?['display_name'] as String?;
    final review = !incoming && row['status'] == 'submitted'
        ? data.reviewFor(row['id'] as String)
        : null;
    return ListTile(
      leading: Icon(icon, color: tone, size: 19),
      title: Text(project?['title'] as String? ?? 'Project'),
      titleTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: workshopText,
      ),
      subtitleTextStyle: const TextStyle(fontSize: 11, color: workshopMuted),
      subtitle: Text(
        !incoming && reviewer != null ? '$label · $reviewer' : label,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: review != null && project != null
          ? () => _readReview(review, project)
          : () => _select(
              _Area.reviews,
              reviews: incoming
                  ? _ReviewFilter.assigned
                  : row['status'] == 'submitted'
                  ? _ReviewFilter.received
                  : _ReviewFilter.awaiting,
            ),
    );
  }

  Widget _projects(WorkspaceData data) {
    final teamProjects = data.projects.map((project) => project['id']).toSet();
    final items = _community
        ? data.community.where(
            (project) => !teamProjects.contains(project['id']),
          )
        : data.projects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('My projects & teams'),
              selected: !_community,
              onSelected: (_) => setState(() => _community = false),
            ),
            ChoiceChip(
              label: const Text('Community'),
              selected: _community,
              onSelected: (_) => setState(() => _community = true),
            ),
            WorkshopAction(
              key: _tourStep == WalkthroughStep.create ? _tourTarget : null,
              onPressed: _tourStep == WalkthroughStep.create
                  ? _tryTourControl
                  : _busy
                  ? null
                  : _createProject,
              icon: Icons.add,
              label: 'New project',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_tourStep == WalkthroughStep.publish ||
            _tourStep == WalkthroughStep.evaluate ||
            _tourStep == WalkthroughStep.results)
          _projectTile(_practiceProject, owned: !_community, practice: true),
        if (items.isEmpty && _tourStep == null)
          _Blank(
            icon: Icons.layers_outlined,
            title: _community ? 'No community projects yet' : 'No projects yet',
          )
        else
          for (final project in items)
            _projectTile(project, owned: !_community),
      ],
    );
  }

  Widget _projectTile(
    WorkspaceRow project, {
    required bool owned,
    bool practice = false,
  }) => _Surface(
    child: ListTile(
      leading: Icon(
        owned && project['visibility'] == 'private'
            ? Icons.lock_outline
            : Icons.layers_outlined,
      ),
      title: practice && _tourStep == WalkthroughStep.publish
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(project['title'] as String, key: _tourTarget),
            )
          : Text(project['title'] as String),
      subtitle: Text(
        practice
            ? (_community ? 'Practice project · Community' : 'Practice project')
            : '${project['category']} · ${project['visibility'] == 'private' ? 'Private' : 'Community'}',
      ),
      trailing: owned
          ? TextButton(
              key: practice && _tourStep == WalkthroughStep.results
                  ? _tourTarget
                  : null,
              onPressed: practice
                  ? _tryTourControl
                  : () => _showResponses(project),
              child: const Text('Responses'),
            )
          : hasNativeQuestionnaire(project) &&
                project['visibility'] == 'community'
          ? FilledButton.tonal(
              key: practice ? _tourTarget : null,
              onPressed: practice
                  ? _tryTourControl
                  : () => _evaluateCommunityProject(project),
              child: const Text('Evaluate'),
            )
          : const Icon(Icons.chevron_right),
      onTap: practice
          ? _tryTourControl
          : () => _showProject(project, team: owned),
    ),
  );

  static const _practiceQuestionnaire = QuestionnaireChoice(
    id: 'practice',
    title: 'Sample usability check',
    form: QuestionnaireForm(
      title: 'Sample usability check',
      items: [
        (
          section: 'Usability',
          prompt: 'How easy was it to find a study space?',
        ),
      ],
    ),
  );

  WorkspaceRow get _practiceProject => {
    'title': 'Campus Study Finder',
    'category': 'Website',
    'summary': 'A sample website that helps students find a place to study.',
    'test_instructions':
        'Imagine looking for a quiet study space. Rate how easy it would be to find the right room.',
    'questionnaire_form': _practiceQuestionnaire.form!.toJson(),
    ...?_tourDraft,
    'artifact_url': null,
    'visibility': _community || _tourShared ? 'community' : 'private',
  };

  Future<bool> _createPracticeProject() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProjectForm(
        practice: true,
        save: (draft) async {
          _tourDraft = draft;
          _tourReview = null;
          _tourShared = false;
        },
        questionnaires: [_practiceQuestionnaire, ...freeQuestionnaires],
        previewQuestionnaire: (form) => previewQuestionnaire(context, form),
        editQuestionnaire: (form) => editQuestionnaire(context, initial: form),
      ),
    );
    return saved == true;
  }

  Future<bool> _sharePracticeProject() async {
    final project = _practiceProject;
    final share = GlobalKey();
    final chosen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => PracticeFormGuide(
        label: 'Sharing practice',
        tips: [
          PracticeTip(
            share,
            'Choose who can evaluate',
            'Share with community lets signed-in members evaluate the project. For a private review, invite specific evaluators. You can also add collaborators through Team workspace.',
          ),
        ],
        total: 1,
        advanceLabel: 'Continue to confirmation',
        advance: () => Navigator.pop(dialogContext, true),
        child: AlertDialog(
          title: Text(project['title'] as String),
          content: SizedBox(
            width: 470,
            child: SingleChildScrollView(child: _projectBrief(project)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              key: share,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Share with community'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || chosen != true) return false;
    _tourShared = await confirmWorkspaceAction(
      context,
      title: 'Share with the community?',
      message:
          'In your workspace, this makes your project available to members. This practice project stays in the tour.',
      action: 'Share project',
    );
    return _tourShared;
  }

  Future<bool> _evaluatePracticeProject() async {
    final project = _practiceProject;
    final criteria = await _repo.projectCriteria(project);
    if (!mounted) return false;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ReviewForm(
        practice: true,
        criteria: criteria,
        questionnaire: projectQuestionnaire(project),
        projectBrief: _projectBrief(
          {
            ...project,
            'test_instructions':
                'Find a quiet study space with a power outlet in the sample site.',
          },
          answering: true,
          openPractice: _openPracticeArtifact,
        ),
        allowUnassessed: false,
        externalOnly: false,
        save: (draft) async => _tourReview = draft,
      ),
    );
    return submitted == true;
  }

  Future<bool> _viewPracticeResponses() async {
    final project = _practiceProject;
    final criteria = await _repo.projectCriteria(project);
    if (!mounted) return false;
    final labels = {
      for (final criterion in criteria)
        criterion['criterion_key'] as String: criterion['prompt'] as String,
    };
    await _showResponses(
      project,
      loadResponses: () async => [
        {
          'round': 'Practice review',
          'round_id': null,
          'created_at': DateTime.now().toIso8601String(),
          'scores': _tourReview?.scores ?? {labels.keys.first: 4},
          'feedback':
              _tourReview?.feedback ??
              'The room filters are easy to find. Add a filter for available seats.',
          'respondent_details': _tourReview?.respondentDetails ?? const [],
          'labels': labels,
        },
      ],
    );
    return true;
  }

  Future<bool> _previewTourTemplate() async {
    await previewQuestionnaire(context, freeQuestionnaires.first.form!);
    return true;
  }

  Future<void> _openPracticeArtifact() {
    var quietOnly = false;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Campus Study Finder'),
          content: SizedBox(
            width: 370,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Find a quiet study space with a power outlet.'),
                  const SizedBox(height: 12),
                  FilterChip(
                    label: const Text('Quiet rooms'),
                    selected: quietOnly,
                    onSelected: (value) => setState(() => quietOnly = value),
                  ),
                  const SizedBox(height: 8),
                  if (!quietOnly)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.groups_outlined),
                      title: Text('Group study lounge'),
                      subtitle: Text('Group conversations · Power outlets'),
                    ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.volume_off_outlined),
                    title: Text('Library room 204'),
                    subtitle: Text('Quiet · Power outlets'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.volume_off_outlined),
                    title: Text('Reading garden'),
                    subtitle: Text('Quiet · No power outlets'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back to evaluation'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProject(WorkspaceRow project, {required bool team}) async {
    final owned = project['creator_id'] == widget.userId;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(project['title'] as String),
        content: SizedBox(
          width: 470,
          child: SingleChildScrollView(child: _projectBrief(project)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (team)
            TextButton(
              onPressed: () => Navigator.pop(context, 'responses'),
              child: const Text('Responses'),
            ),
          if (team)
            TextButton(
              onPressed: () => Navigator.pop(context, 'team'),
              child: const Text('Team workspace'),
            ),
          if (owned) ...[
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit-form'),
              child: const Text('Edit questionnaire'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(context, 'visibility'),
              child: Text(
                project['visibility'] == 'private'
                    ? 'Share with community'
                    : 'Make private',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'directory'),
              child: const Text('Find evaluators'),
            ),
          ] else if (!team && project['visibility'] == 'community') ...[
            if (hasNativeQuestionnaire(project))
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, 'evaluate'),
                child: const Text('Evaluate'),
              ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, 'report'),
              child: const Text('Report'),
            ),
          ],
        ],
      ),
    );
    if (!mounted) return;
    final id = project['id'] as String;
    if (result == 'responses') {
      await _showResponses(project);
      return;
    }
    if (result == 'evaluate') {
      await _evaluateCommunityProject(project);
      return;
    }
    if (result == 'edit-form') {
      final saved = await editQuestionnaire(
        context,
        initial: projectQuestionnaire(project),
        save: (form) => _repo.updateProjectQuestionnaire(id, form),
      );
      if (mounted && saved != null) {
        _refresh();
        _notice('Questionnaire updated');
      }
      return;
    }
    if (result == 'team') {
      final directory = (await _data).directory;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(project['title']),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: ProjectTeamTools(
                repository: _repo,
                project: project,
                directory: directory,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (mounted) _refresh();
    }
    if (result == 'directory') _select(_Area.directory);
    if (mounted && result == 'visibility') {
      final share = project['visibility'] == 'private';
      await _confirmChange(
        title: share
            ? 'Share with the community?'
            : 'Make this project private?',
        action: share ? 'Share project' : 'Make private',
        subject: project['title'],
        message: share
            ? 'Signed-in members will be able to see the project brief and link.${hasNativeQuestionnaire(project) ? ' They can submit an evaluation from the post.' : ''}'
            : 'This removes the project from the community. The team and invited evaluators keep their existing access.',
        done: 'Visibility updated',
        perform: () => _repo.setVisibility(id, share),
      );
    }
    if (mounted && result == 'report') {
      final values = await workspaceForm(
        context,
        title: 'Report project',
        action: 'Submit report',
        fields: const [
          FormFieldSpec('reason', 'Reason', required: true, max: 500, lines: 3),
        ],
      );
      if (mounted && values != null) {
        await _change(
          () => _repo.report(id, values['reason'] as String),
          'Report submitted',
        );
      }
    }
  }

  Future<void> _showResponses(
    WorkspaceRow project, {
    Future<List<WorkspaceRow>> Function()? loadResponses,
  }) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(loadResponses == null ? 'Responses' : 'Practice responses'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: ProjectResponses(
            repository: _repo,
            project: project,
            loadResponses: loadResponses,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _evaluateCommunityProject(WorkspaceRow project) async {
    try {
      final assignment = await _repo.client
          .from('review_assignments')
          .select('id,status')
          .eq('project_id', project['id'])
          .eq('evaluator_id', widget.userId)
          .isFilter('round_id', null)
          .maybeSingle();
      if (!mounted) return;
      if (assignment?['status'] == 'declined') {
        _notice(
          'You already declined the invitation to this project.',
          tone: NoticeTone.info,
        );
        return;
      }
      if (assignment?['status'] == 'submitted') {
        final review = await _repo.client
            .from('reviews')
            .select()
            .eq('assignment_id', assignment!['id'])
            .single();
        if (mounted) await _readReview(review, project);
        return;
      }
      await _writeReview(null, project);
    } catch (error) {
      if (mounted) _notice(workspaceError(error), tone: NoticeTone.error);
    }
  }

  Widget _questionnaireLibrary() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Pick a free template or build a questionnaire for your next project.',
      ),
      const SizedBox(height: 18),
      _heading('Free templates'),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final template in freeQuestionnaires)
                SizedBox(
                  width: width >= 700 ? (width - 12) / 2 : width,
                  child: _questionnaireCard(template),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 26),
      _heading('My questionnaires'),
      const Text(
        'Saved to your account. Choose them when you create a project.',
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => _editSavedQuestionnaire(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New questionnaire'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      FutureBuilder<List<QuestionnaireChoice>>(
        future: _savedQuestionnaires,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppNotice(
                  'Couldn’t load your questionnaires',
                  tone: NoticeTone.error,
                ),
                TextButton(
                  onPressed: _refreshQuestionnaires,
                  child: const Text('Try again'),
                ),
              ],
            );
          }
          final saved = snapshot.data;
          if (saved == null) {
            return const SkeletonRows(label: 'Loading questionnaires');
          }
          if (saved.isEmpty) {
            return const Text('Your saved questionnaires will appear here.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in saved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _questionnaireCard(item),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _questionnaireCard(QuestionnaireChoice choice) {
    final form = choice.form;
    final asset = choice.asset;
    final file = choice.filePath;
    final previewTarget =
        _tourStep == WalkthroughStep.templates &&
        choice.id == freeQuestionnaires.first.id;
    return _Surface(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              form == null
                  ? Icons.attach_file_outlined
                  : Icons.list_alt_outlined,
              color: workshopIce,
            ),
            const SizedBox(height: 8),
            Text(choice.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              form == null
                  ? choice.fileName!
                  : '${form.items.length} questions · 1–${form.levels.length} scale',
              style: const TextStyle(color: workshopMuted),
            ),
            if (choice.id == 'iso-worksheet')
              const Text('Includes starter questions for the nine sections.'),
            if (choice.id == 'mars-worksheet')
              const Text('Four-point worksheet for non-entertainment apps.'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (form != null) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _editSavedQuestionnaire(choice),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(asset == null ? 'Edit' : 'Edit a copy'),
                  ),
                  TextButton(
                    key: previewTarget ? _tourTarget : null,
                    onPressed: previewTarget
                        ? _tryTourControl
                        : () => previewQuestionnaire(context, form),
                    child: const Text('Preview'),
                  ),
                ],
                if (file != null)
                  TextButton.icon(
                    onPressed: () =>
                        _downloadQuestionnaire(file, choice.fileName!),
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Download file'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _refreshQuestionnaires() {
    setState(() => _savedQuestionnaires = _repo.savedQuestionnaires());
  }

  Future<void> _editSavedQuestionnaire([QuestionnaireChoice? choice]) async {
    final form = await editQuestionnaire(
      context,
      initial: choice?.form,
      save: (form) => _repo.saveQuestionnaire(
        form,
        id: choice?.asset == null ? choice?.id : null,
      ),
    );
    if (!mounted || form == null) return;
    _refreshQuestionnaires();
    _notice('Questionnaire saved');
  }

  Widget _projectBrief(
    WorkspaceRow project, {
    bool answering = false,
    VoidCallback? openPractice,
  }) {
    final source = questionnaireSources[project['rubric_id']];
    final custom = project['custom_questions'] as List<dynamic>?;
    final link = project['artifact_url'] as String?;
    final questionnaire = project['questionnaire_url'] as String?;
    final pdfPath = project['questionnaire_file_path'] as String?;
    final pdfName = project['questionnaire_file_name'] as String?;
    final form = projectQuestionnaire(project);
    final audience = project['audience'] as String?;
    final instructions = project['test_instructions'] as String?;
    final label = source != null
        ? project['rubric_id'] == 'website-iso25010-v1'
              ? 'Website quality · ISO/IEC 25010:2023-informed'
              : 'Mobile app quality · MARS-informed'
        : custom != null
        ? 'Custom questionnaire · ${custom.length} questions'
        : project['rubric_id'] != null
        ? 'Built-in questionnaire'
        : form?.title ??
              (pdfName == null
                  ? 'External questionnaire'
                  : 'Questionnaire · $pdfName');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${project['category']} · ${project['visibility'] == 'private' ? 'Private' : 'Community'}',
          style: const TextStyle(color: workshopMuted),
        ),
        const SizedBox(height: 10),
        SelectableText(project['summary'] as String),
        if (link != null || openPractice != null) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: openPractice ?? () => _openUrl(link!),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open project'),
          ),
        ],
        if (audience != null && audience.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Intended users',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SelectableText(audience),
        ],
        if (instructions != null && instructions.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'What to try',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SelectableText(instructions),
        ],
        const SizedBox(height: 14),
        Text(label, style: const TextStyle(color: workshopIce)),
        if ((!answering || !hasNativeQuestionnaire(project)) &&
            (questionnaire != null ||
                source != null ||
                pdfPath != null ||
                form != null))
          Wrap(
            spacing: 8,
            children: [
              if (form != null)
                TextButton.icon(
                  onPressed: () => previewQuestionnaire(context, form),
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: const Text('Preview questionnaire'),
                ),
              if (pdfPath != null)
                TextButton.icon(
                  onPressed: () => _downloadQuestionnaire(pdfPath, pdfName!),
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: const Text('Download questionnaire'),
                ),
              if (questionnaire != null)
                TextButton.icon(
                  onPressed: () => _openUrl(questionnaire),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Open questionnaire'),
                ),
              if (source != null)
                TextButton(
                  onPressed: () => _openUrl(source.url),
                  child: Text(source.name),
                ),
            ],
          ),
      ],
    );
  }

  void _downloadQuestionnaire(String path, String name) {
    final download = _repo.questionnaireDownloadUrl(path);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => FutureBuilder<String>(
        future: download,
        builder: (_, snapshot) => AlertDialog(
          title: Text(name),
          content: snapshot.connectionState == ConnectionState.waiting
              ? const SizedBox(
                  width: 250,
                  child: SkeletonRows(label: 'Preparing download', count: 1),
                )
              : Text(
                  snapshot.hasError
                      ? 'Couldn’t prepare the download.'
                      : 'The download link is valid for one minute.',
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            if (snapshot.hasData)
              FilledButton.icon(
                onPressed: () {
                  _openUrl(snapshot.data!);
                  Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.download_outlined, size: 17),
                label: const Text('Download file'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createProject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final savedQuestionnaires = await _repo.savedQuestionnaires();
      if (!mounted) return;
      setState(() => _busy = false);
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProjectForm(
          save: _repo.createProject,
          questionnaires: [...freeQuestionnaires, ...savedQuestionnaires],
          previewQuestionnaire: (form) => previewQuestionnaire(context, form),
          editQuestionnaire: (form) =>
              editQuestionnaire(context, initial: form),
        ),
      );
      if (mounted && saved == true) {
        _refresh();
        _notice('Project created');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _notice(workspaceError(error), tone: NoticeTone.error);
      }
    }
  }

  Widget _directory(WorkspaceData data) {
    final people = data.directory.where((row) {
      if (_evaluatorType != null && row['evaluator_type'] != _evaluatorType) {
        return false;
      }
      final profession = professions[row['profession']] ?? '';
      final searchable =
          '${row['display_name']} ${row['expertise']} ${row['headline']} $profession';
      return searchable.toLowerCase().contains(_query);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search name, profession, or expertise',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('All types'),
              selected: _evaluatorType == null,
              onSelected: (_) => setState(() => _evaluatorType = null),
            ),
            for (final type in evaluatorTypes.entries)
              ChoiceChip(
                label: Text(type.value),
                selected: _evaluatorType == type.key,
                onSelected: (_) => setState(() => _evaluatorType = type.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (people.isEmpty)
          const _Blank(
            icon: Icons.group_outlined,
            title: 'No evaluators found',
          ),
        for (final person in people)
          _Surface(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF203756),
                child: Icon(Icons.person_outline, color: workshopMuted),
              ),
              title: Text(person['display_name'] as String),
              subtitle: Text(
                [
                      evaluatorTypes[person['evaluator_type']],
                      professions[person['profession']],
                      person['headline'],
                      if (person['email_confirmed'] == true) 'Email confirmed',
                    ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showEvaluator(person, data),
            ),
          ),
      ],
    );
  }

  Future<void> _showEvaluator(WorkspaceRow person, WorkspaceData data) async {
    final projects = data.projects
        .where((project) => project['creator_id'] == widget.userId)
        .toList();
    final projectId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(person['display_name'] as String),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(evaluatorTypes[person['evaluator_type']] ?? 'Evaluator'),
                if (professions[person['profession']] case final profession?)
                  Text('$profession · Self-reported'),
                if (person['email_confirmed'] == true)
                  const Text(
                    'Email confirmed',
                    style: TextStyle(color: workshopIce),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Self-reported expertise',
                  style: TextStyle(color: workshopMuted),
                ),
                const SizedBox(height: 8),
                Text(
                  (person['expertise'] as String).isEmpty
                      ? 'No expertise listed'
                      : person['expertise'] as String,
                ),
                if (person['portfolio_url'] != null)
                  TextButton.icon(
                    onPressed: () =>
                        _openUrl(person['portfolio_url'] as String),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Portfolio'),
                  ),
                const SizedBox(height: 16),
                ReviewerTrust(repository: _repo, reviewer: person['id']),
                const SizedBox(height: 16),
                Text(
                  projects.isEmpty
                      ? 'No projects available to invite for.'
                      : 'Invite to review a project',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final project in projects)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(project['title'] as String),
                    trailing: const Icon(Icons.arrow_outward, size: 18),
                    onTap: _busy
                        ? null
                        : () => Navigator.pop(context, project['id']),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted || projectId == null) return;
    final rounds = await projectRounds(_repo, projectId).catchError((
      Object error,
    ) {
      if (mounted) _notice(workspaceError(error), tone: NoticeTone.error);
      return <WorkspaceRow>[];
    });
    if (!mounted) return;
    final previous = data.assignments.where(
      (row) =>
          row['project_id'] == projectId && row['evaluator_id'] == person['id'],
    );
    final unavailable = previous.map((row) => row['round_id']).toSet();
    final options = <String, String>{
      if (!unavailable.contains(null)) '': 'Initial review',
      for (final round in rounds)
        if (!unavailable.contains(round['id'])) round['id']: round['label'],
    };
    if (options.isEmpty) {
      _notice('This evaluator already has an invitation for every round.');
      return;
    }
    String selectedRound = options.keys.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send review invitation?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Text(
                '${person['display_name']} will be able to see the project brief and version link.',
              ),
              WorkspaceSelect<String>(
                label: 'Review round',
                initial: selectedRound,
                choices: options,
                onChanged: (value) => selectedRound = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send invitation'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await _change(
        () => _repo.invite(
          projectId,
          person['id'] as String,
          roundId: selectedRound.isEmpty ? null : selectedRound,
        ),
        'Invitation sent',
      );
    }
  }

  Widget _reviews(WorkspaceData data) {
    final all = _reviewFilter == _ReviewFilter.all;
    final assigned = _reviewFilter == _ReviewFilter.assigned;
    final incoming = data.assignments.where(
      (item) =>
          item['evaluator_id'] == widget.userId && (all || _isOpenReview(item)),
    );
    final outgoing = data.assignments.where(
      (item) =>
          item['evaluator_id'] != widget.userId &&
          switch (_reviewFilter) {
            _ReviewFilter.awaiting => _isOpenReview(item),
            _ReviewFilter.received => item['status'] == 'submitted',
            _ => true,
          },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 4,
          children: [
            for (final filter in _ReviewFilter.values)
              ChoiceChip(
                label: Text(filter.label),
                selected: filter == _reviewFilter,
                onSelected: (_) => setState(() => _reviewFilter = filter),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (!assigned) ...[
          _heading('Project reviews'),
          if (outgoing.isEmpty)
            _Blank(
              icon: Icons.send_outlined,
              title: switch (_reviewFilter) {
                _ReviewFilter.awaiting => 'No reviews awaiting feedback',
                _ReviewFilter.received => 'No feedback received yet',
                _ => 'No invitations sent',
              },
            ),
          for (final item in outgoing) _assignment(item, data, incoming: false),
        ],
        if (all) const SizedBox(height: 25),
        if (all || assigned) ...[
          _heading('Assigned to me'),
          if (incoming.isEmpty)
            _Blank(
              icon: Icons.inbox_outlined,
              title: assigned ? 'You’re caught up' : 'No assignments yet',
            ),
          for (final item in incoming) _assignment(item, data, incoming: true),
        ],
      ],
    );
  }

  Widget _assignment(
    WorkspaceRow assignment,
    WorkspaceData data, {
    required bool incoming,
  }) {
    final status = assignment['status'] as String;
    final baseProject = assignment['projects'] as WorkspaceRow?;
    final round = assignment['round'] as WorkspaceRow?;
    final project = baseProject == null || round == null
        ? baseProject
        : {...baseProject, 'artifact_url': round['artifact_url']};
    final reviewer = assignment['evaluator'] as WorkspaceRow?;
    final id = assignment['id'] as String;
    final review = data.reviewFor(id);
    return _Surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  project?['title'] as String? ?? 'Project',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _Status(status),
                if (round != null) Text(round['label']),
              ],
            ),
            if (!incoming && reviewer != null)
              Text(
                reviewer['display_name'] as String,
                style: const TextStyle(color: workshopMuted),
              ),
            if (project != null || review != null) const SizedBox(height: 8),
            Wrap(
              spacing: 9,
              runSpacing: 5,
              children: [
                if (project != null)
                  TextButton(
                    onPressed: () => _showProject(project, team: !incoming),
                    child: const Text('Project brief'),
                  ),
                if (incoming && status == 'invited') ...[
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _change(
                            () => _repo.respond(id, true),
                            'Invitation accepted',
                          ),
                    child: const Text('Accept'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _confirmChange(
                            title: 'Decline review invitation?',
                            action: 'Decline invitation',
                            subject: project?['title'] as String?,
                            message:
                                'The project team will be notified and this invitation will close.',
                            done: 'Invitation declined',
                            destructive: true,
                            perform: () => _repo.respond(id, false),
                          ),
                    child: const Text('Decline'),
                  ),
                ],
                if (incoming && status == 'accepted' && project != null)
                  FilledButton(
                    onPressed: _busy ? null : () => _writeReview(id, project),
                    child: const Text('Write review'),
                  ),
                if (review != null && project != null)
                  FilledButton.tonal(
                    onPressed: () => _readReview(review, project),
                    child: const Text('View feedback'),
                  ),
                if (status != 'declined')
                  TextButton.icon(
                    onPressed: () =>
                        showReviewConversation(context, _repo, assignment),
                    icon: const Icon(Icons.chat_bubble_outline, size: 17),
                    label: const Text('Conversation'),
                  ),
                if (assignment['creator_id'] == widget.userId &&
                    _isOpenReview(assignment))
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _change(() async {
                            try {
                              await _repo.client.rpc(
                                'send_review_reminder',
                                params: {'p_assignment': id},
                              );
                            } on PostgrestException catch (error) {
                              if (error.code == 'P0001') {
                                throw FormatException(error.message);
                              }
                              rethrow;
                            }
                          }, 'Reminder sent'),
                    child: const Text('Remind evaluator'),
                  ),
                if (!incoming && review != null && project != null)
                  TextButton(
                    onPressed: () async {
                      final saved = await addProjectRevision(
                        context,
                        _repo,
                        project['id'],
                        assignment: id,
                      );
                      if (mounted && saved) _notice('Revision added');
                    },
                    child: const Text('Add revision'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _writeReview(String? assignmentId, WorkspaceRow project) async {
    try {
      final criteria = await _repo.projectCriteria(project);
      final form = projectQuestionnaire(project);
      if (assignmentId == null && !hasNativeQuestionnaire(project)) return;
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReviewForm(
          criteria: criteria,
          questionnaire: form,
          projectBrief: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project['title'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _projectBrief(project, answering: true),
            ],
          ),
          allowUnassessed: questionnaireSources.containsKey(
            project['rubric_id'],
          ),
          externalOnly:
              project['rubric_id'] == null &&
              project['custom_questions'] == null &&
              form == null &&
              hasQuestionnaire(project),
          save: (review) => assignmentId == null
              ? _repo.submitCommunityEvaluation(
                  project['id'],
                  form,
                  review.scores,
                  review.feedback,
                  review.respondentDetails,
                )
              : _repo.submitReview(
                  assignmentId,
                  review.scores,
                  review.feedback,
                  respondentDetails: review.respondentDetails,
                ),
        ),
      );
      if (mounted && saved == true) {
        _refresh();
        _notice('Review submitted');
      }
    } catch (error) {
      if (mounted) _notice(workspaceError(error), tone: NoticeTone.error);
    }
  }

  Future<void> _readReview(WorkspaceRow review, WorkspaceRow project) async {
    try {
      final criteria = await _repo.projectCriteria(project);
      if (!mounted) return;
      final scores = review['scores'] as WorkspaceRow;
      final form = projectQuestionnaire(project);
      final details =
          (review['respondent_details'] as List<dynamic>? ?? const [])
              .cast<String>();
      final highest = form?.levels.length ?? 5;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Evaluation feedback'),
          content: SizedBox(
            width: 470,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final criterion in criteria)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(criterion['label'] as String),
                      trailing: Text(
                        scores[criterion['criterion_key']] == 0
                            ? 'Not assessed'
                            : '${scores[criterion['criterion_key']]} / $highest',
                      ),
                    ),
                  if (criteria.isNotEmpty) const Divider(),
                  if (form != null &&
                      details.any((detail) => detail.isNotEmpty)) ...[
                    Text(
                      'Respondent details',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final (index, detail) in details.indexed)
                      if (detail.isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(form.fields[index]),
                          subtitle: SelectableText(detail),
                        ),
                    const Divider(),
                  ],
                  SelectableText(review['feedback'] as String),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _notice(workspaceError(error), tone: NoticeTone.error);
    }
  }

  Widget _profile(WorkspaceData data) {
    final profile = data.profile;
    final emailConfirmed =
        widget.client.auth.currentUser?.emailConfirmedAt != null;
    return _Surface(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile['display_name'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if ((profile['headline'] as String).isNotEmpty)
              Text(profile['headline'] as String),
            if (professions[profile['profession']] case final profession?)
              Text(profession),
            const SizedBox(height: 12),
            Text(
              emailConfirmed ? 'Email confirmed' : 'Email confirmation pending',
            ),
            Text(
              profile['directory_visible'] == true
                  ? 'Listed in evaluator directory'
                  : 'Hidden from evaluator directory',
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the same account to create projects and accept review invitations. You can choose whether to appear in the evaluator directory.',
              style: TextStyle(color: workshopMuted),
            ),
            if ((profile['expertise'] as String).isNotEmpty)
              Text('Expertise · ${profile['expertise']}'),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () async {
                      final values = await workspaceForm(
                        context,
                        title: 'Edit profile',
                        action: 'Save profile',
                        initial: profile,
                        directory: true,
                        fields: const [
                          FormFieldSpec(
                            'display_name',
                            'Display name',
                            required: true,
                            max: 80,
                          ),
                          FormFieldSpec('headline', 'Headline', max: 120),
                          FormFieldSpec(
                            'expertise',
                            'Expertise',
                            max: 240,
                            lines: 2,
                          ),
                          FormFieldSpec(
                            'portfolio_url',
                            'Portfolio link',
                            max: 500,
                            url: true,
                          ),
                        ],
                      );
                      if (mounted && values != null) {
                        await _change(
                          () => _repo.saveProfile(values),
                          'Profile updated',
                        );
                      }
                    },
              child: const Text('Edit profile'),
            ),
            const SizedBox(height: 22),
            AccountSecuritySettings(client: widget.client),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _savingTour
                  ? null
                  : () {
                      final firstRun = _tourStep != null && !_replayingTour;
                      _replayingTour = !firstRun;
                      _showTourStep(WalkthroughStep.overview);
                    },
              icon: const Icon(Icons.tour_outlined, size: 17),
              label: const Text('Start workspace tour'),
            ),
            const SizedBox(height: 22),
            CredentialWorkflow(repository: _repo),
          ],
        ),
      ),
    );
  }

  Widget _moderation(WorkspaceData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CredentialWorkflow(repository: _repo, staff: true),
      const SizedBox(height: 24),
      _heading('Open reports'),
      if (data.reports.isEmpty)
        const _Blank(icon: Icons.shield_outlined, title: 'No open reports'),
      for (final report in data.reports)
        _Surface(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(report['reason'] as String),
                const SizedBox(height: 8),
                Text(
                  (report['projects'] as WorkspaceRow?)?['title'] as String? ??
                      'Project ID · ${report['project_id']}',
                  style: const TextStyle(color: workshopMuted),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _confirmChange(
                              title: 'Dismiss report?',
                              action: 'Dismiss report',
                              message:
                                  'This closes the report and removes it from the moderation queue.',
                              done: 'Report dismissed',
                              destructive: true,
                              perform: () => _repo.moderate(
                                report['id'] as String,
                                'dismissed',
                              ),
                            ),
                      child: const Text('Dismiss'),
                    ),
                    FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () => _confirmChange(
                              title: 'Resolve report?',
                              action: 'Resolve report',
                              message:
                                  'This marks the report as resolved and removes it from the moderation queue.',
                              done: 'Report resolved',
                              perform: () => _repo.moderate(
                                report['id'] as String,
                                'resolved',
                              ),
                            ),
                      child: const Text('Resolve'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Future<void> _confirmChange({
    required String title,
    required String action,
    required String message,
    required String done,
    required Future<void> Function() perform,
    bool destructive = false,
    String? subject,
  }) async {
    final confirmed = await confirmWorkspaceAction(
      context,
      title: title,
      action: action,
      message: message,
      subject: subject,
      destructive: destructive,
      perform: perform,
    );
    if (!mounted || !confirmed) return;
    _refresh();
    _notice(done);
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      if (await launchUrl(uri, webOnlyWindowName: '_blank')) return;
    } catch (_) {
      // Show the same message if the browser refuses to open the link.
    }
    if (mounted) _notice('Couldn’t open this link.', tone: NoticeTone.error);
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: workshopMuted,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: WorkshopGlass(child: child),
  );
}

class _WorkspaceLoading extends StatelessWidget {
  const _WorkspaceLoading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LoadingSkeleton(
          label: 'Loading workspace',
          child: Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBlock(height: 24, width: 172),
          ),
        ),
        const SizedBox(height: 18),
        WorkshopGlass(
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonRows(
              label: 'Loading workspace content',
              leading: true,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Blank extends StatelessWidget {
  const _Blank({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: workshopIce, size: 28),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: workshopMuted),
          ),
          ?action,
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.value, this.icon, this.onTap);
  final String title;
  final int value;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Surface(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: workshopMuted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: workshopMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      color: workshopText,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 14,
                  color: workshopMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _KitTag extends StatelessWidget {
  const _KitTag(this.icon, this.label, {this.attention = false});
  final IconData icon;
  final String label;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final color = attention ? const Color(0xFFFFD99D) : workshopIce;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label, style: TextStyle(color: color, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.state);
  final String state;

  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = switch (state) {
      'accepted' => ('Accepted', workshopIce, const Color(0x544991E1)),
      'submitted' => (
        'Submitted',
        const Color(0xFFB6F3D8),
        const Color(0x4842AE82),
      ),
      'declined' => (
        'Declined',
        const Color(0xFFFFC9CC),
        const Color(0x46D16D76),
      ),
      _ => ('Invited', const Color(0xFFFFD99D), const Color(0x48C28C46)),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
