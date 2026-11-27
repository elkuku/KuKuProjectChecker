import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../support/github_repos.dart';
import '../support/repo_status.dart';
import '../support/site.dart';

/// The parts of a project that are not an environment. The address and deploy remote
/// are edited in the Environments dialog.
typedef SiteDetails = ({
  String name,
  String repoPath,
  String githubRepo,
  String devUrl
});

/// Asks for a folder, starting in [initialDirectory]; null if the user cancelled.
typedef PickFolder = Future<String?> Function(String? initialDirectory);

/// The system's folder chooser.
Future<String?> pickFolder(String? initialDirectory) => getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: 'Choose',
    );

/// Asks for a project's required identity and optional dev site; [site] is the one to
/// edit, or null to add a new one. Returns the details, or null if cancelled.
Future<SiteDetails?> showSiteDialog(BuildContext context,
        {Site? site,
        PickFolder pickFolder = pickFolder,
        GitHubRepoLookup listGitHubRepos = lookupGitHubRepos}) =>
    showDialog<SiteDetails>(
      context: context,
      builder: (_) => _SiteDialog(
        site: site,
        pickFolder: pickFolder,
        listGitHubRepos: listGitHubRepos,
      ),
    );

/// [path] with the home folder written as ~, like the paths typed in by hand.
String collapseHome(String path) {
  final dir = Platform.environment['HOME'];
  if (dir == null || dir.isEmpty) return path;
  if (path == dir) return '~';

  return path.startsWith('$dir/') ? '~${path.substring(dir.length)}' : path;
}

/// The found-repo status is green in both themes.
Color githubFoundColor(BuildContext context) => Theme.of(context).brightness ==
        Brightness.dark
    ? Colors.greenAccent.shade400
    : Colors.green.shade700;

class _SiteDialog extends StatefulWidget {
  final Site? site;
  final PickFolder pickFolder;
  final GitHubRepoLookup listGitHubRepos;

  const _SiteDialog({
    this.site,
    required this.pickFolder,
    required this.listGitHubRepos,
  });

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  final form = GlobalKey<FormState>();

  late final name = TextEditingController(text: widget.site?.name ?? '');
  late final repoPath =
      TextEditingController(text: widget.site?.repoPath ?? '');
  late final githubRepo =
      TextEditingController(text: widget.site?.githubRepo ?? '');
  late final devUrl = TextEditingController(text: widget.site?.devUrl ?? '');

  bool showErrors = false;

  /// Similar repositories found by gh, best first; the user can choose one.
  List<GitHubRepo> githubCandidates = const [];

  /// The candidate currently offered as the suggestion.
  GitHubRepo? selectedRepo;

  /// True while the gh lookup is running, so the field does not claim "no match" early.
  bool githubLookupPending = false;

  /// gh is a requirement; a failed lookup is shown instead of guessing a URL.
  String? githubLookupError;

  bool get isNew => widget.site == null;

  /// Only old records get suggestions: a new project has no address to derive them from.
  String get nameSuggestion => widget.site?.suggestedName ?? '';
  String get repoSuggestion => widget.site?.suggestedRepoPath ?? '';
  String get githubSuggestion => selectedRepo?.url ?? '';

  /// Shown below the field: an error replaces helperText while autovalidating.
  String get githubStatusText {
    if (githubLookupPending) return 'Searching GitHub with gh…';
    if (githubLookupError != null) {
      return 'GitHub lookup failed: $githubLookupError';
    }
    if (selectedRepo != null) {
      return 'Existing repo: ${selectedRepo!.nameWithOwner}';
    }
    return 'No matching repository found with gh';
  }

  String get githubSuggestionTooltip => 'Use existing GitHub repository';

  bool get hasMissingFields =>
      widget.site != null && widget.site!.missingRequiredFields.isNotEmpty;

  /// The error names the missing field and offers the derived value as a suggestion.
  String? _error(String? error, String text, String suggestion) => error != null &&
          text.trim().isEmpty && suggestion.isNotEmpty
      ? '$error — suggested: $suggestion'
      : error;

  String? _githubError(String? error, String text) {
    final message = _error(error, text, githubSuggestion);
    if (message == null || selectedRepo == null) return message;
    return '$message (existing repo)';
  }

  /// Looks up an existing repository with a similar name through gh. The CLI is
  /// required: failures are shown in the field, never replaced by a guessed URL.
  Future<void> _findExistingRepo() async {
    final site = widget.site;
    if (site == null || site.githubRepo.trim().isNotEmpty) return;

    final label = site.suggestedGitHubLabel;
    if (label.isEmpty) return;

    githubLookupPending = true;

    final List<GitHubRepo> repos;
    try {
      repos = await widget.listGitHubRepos();
    } catch (error) {
      final message = error is StateError ? error.message : '$error';
      if (mounted) {
        setState(() {
          githubLookupPending = false;
          githubLookupError = message;
        });
      }
      return;
    }
    if (!mounted) return;

    setState(() {
      githubLookupPending = false;
      githubCandidates = similarGitHubRepos(repos, label);
      selectedRepo = githubCandidates.isEmpty ? null : githubCandidates.first;
    });
  }

  @override
  void initState() {
    super.initState();
    _findExistingRepo();
  }

  Widget? _suggestionButton(
      String value, String tooltip, TextEditingController controller) {
    if (value.isEmpty) return null;
    return IconButton(
      icon: const Icon(Icons.auto_fix_high, size: 18),
      tooltip: tooltip,
      onPressed: () => setState(() => controller.text = value),
    );
  }

  @override
  void dispose() {
    name.dispose();
    repoPath.dispose();
    githubRepo.dispose();
    devUrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!form.currentState!.validate()) {
      setState(() => showErrors = true);
      return;
    }

    Navigator.of(context).pop((
      name: name.text.trim(),
      repoPath: repoPath.text.trim(),
      githubRepo: githubRepo.text.trim(),
      devUrl: devUrl.text.trim(),
    ));
  }

  /// Lets the user choose the repository folder; starts in the folder in the field if it
  /// exists, else in ~/repos or the home folder.
  Future<void> _chooseFolder() async {
    final current = RepoStatus.expandHome(repoPath.text.trim());
    final home = Platform.environment['HOME'] ?? '';
    final start = [current, '$home/repos', home].firstWhere(
        (dir) => dir.isNotEmpty && Directory(dir).existsSync(),
        orElse: () => '');

    final chosen = await widget.pickFolder(start.isEmpty ? null : start);
    if (chosen == null || !mounted) return;

    repoPath.text = collapseHome(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(isNew ? 'Add site' : 'Edit site'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: form,
          autovalidateMode: showErrors || hasMissingFields
              ? AutovalidateMode.always
              : AutovalidateMode.disabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: isNew,
                decoration: InputDecoration(
                  labelText: 'Display name',
                  hintText: nameSuggestion.isNotEmpty ? nameSuggestion : 'Shop',
                  suffixIcon: _suggestionButton(
                      nameSuggestion, 'Use suggested display name', name),
                ),
                validator: (text) =>
                    _error(Site.nameError(text ?? ''), text ?? '', nameSuggestion),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: repoPath,
                decoration: InputDecoration(
                  labelText: 'Local repository',
                  hintText: repoSuggestion.isNotEmpty ? repoSuggestion : '~/repos/shop',
                  helperText:
                      'Shows the repository status, its changes and deploys',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_suggestionButton(repoSuggestion,
                              'Use suggested local repository', repoPath) case final button?)
                        button,
                      IconButton(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Choose the folder',
                        onPressed: _chooseFolder,
                      ),
                    ],
                  ),
                ),
                validator: (text) => _error(
                    Site.repoPathError(text ?? ''), text ?? '', repoSuggestion),
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: githubRepo,
                decoration: InputDecoration(
                  labelText: 'GitHub repository',
                  hintText: githubSuggestion.isNotEmpty
                      ? githubSuggestion
                      : 'https://github.com/owner/repo',
                  helperText: 'The project’s source on GitHub',
                  suffixIcon: _suggestionButton(
                      githubSuggestion, githubSuggestionTooltip, githubRepo),
                ),
                keyboardType: TextInputType.url,
                validator: (text) =>
                    _githubError(Site.githubRepoError(text ?? ''), text ?? ''),
                onFieldSubmitted: (_) => _save(),
              ),
              if (widget.site?.githubRepo.trim().isEmpty ?? false) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    githubStatusText,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: selectedRepo == null
                              ? null
                              : githubFoundColor(context),
                          fontWeight: selectedRepo == null
                              ? null
                              : FontWeight.w600,
                        ),
                  ),
                ),
                if (githubCandidates.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 0, 0),
                    child: Row(
                      children: [
                        Text('Choose:',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<GitHubRepo>(
                            value: selectedRepo,
                            isDense: true,
                            isExpanded: true,
                            items: [
                              for (final repo in githubCandidates)
                                DropdownMenuItem<GitHubRepo>(
                                  value: repo,
                                  child: Text(
                                    repo.nameWithOwner,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: githubFoundColor(context),
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (repo) {
                              if (repo != null) {
                                setState(() => selectedRepo = repo);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: devUrl,
                decoration: const InputDecoration(
                  labelText: 'Dev site URL',
                  hintText: 'https://dev.shop.example.com',
                  helperText:
                      'Optional; a version that deploys itself from the upstream branch',
                ),
                keyboardType: TextInputType.url,
                validator: (text) => (text ?? '').trim().isEmpty
                    ? null
                    : Site.urlError(text!),
                onFieldSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
