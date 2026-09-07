import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String appVersion = '19.0';

void main() => runApp(const PianoPracticeApp());

int _idCounter = 0;
String newId() {
  _idCounter += 1;
  return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
}

// ---------------------------------------------------------------------------
// Modeles
// ---------------------------------------------------------------------------

const List<String> projectStatuses = [
  'À découvrir',
  'En cours de déchiffrement',
  'En mémorisation',
  'Acquis',
  'Répertoire d’entretien',
];

String _normalizeProjectStatus(String? value) {
  if (value == 'À réviser') return 'Répertoire d’entretien';
  if (value == 'En cours') return 'En cours de déchiffrement';
  return projectStatuses.contains(value) ? value! : 'En cours de déchiffrement';
}

/// Déduit le statut à partir des 4 étapes détaillées.
/// Le statut reste volontairement simple et lisible : la progression est jugée
/// dans l'ordre naturel du travail d'un morceau.
String statusFromStages({
  required double reading,
  required double handsTogether,
  required double memory,
  required double interpretation,
}) {
  final values = [reading, handsTogether, memory, interpretation];
  final maxValue = values.reduce((a, b) => a > b ? a : b);
  final minValue = values.reduce((a, b) => a < b ? a : b);
  if (maxValue <= 0.001) return 'À découvrir';
  if (reading < 0.50 || handsTogether < 0.50) return 'En cours de déchiffrement';
  if (memory < 0.70) return 'En mémorisation';
  if (interpretation < 0.80 || minValue < 0.80) return 'Acquis';
  if (minValue >= 0.90) return 'Acquis';
  return 'En mémorisation';
}

String projectStatusEmoji(String status) {
  switch (status) {
    case 'À découvrir': return '🌱';
    case 'En cours de déchiffrement': return '🔎';
    case 'En mémorisation': return '🧠';
    case 'Acquis': return '✅';
    case 'Répertoire d’entretien': return '🎼';
    default: return '🎵';
  }
}

class Project {
  Project({
    required this.id,
    required this.name,
    required this.progress,
    required this.goal,
    this.method,
    this.priority = false,
    this.status = 'En cours de déchiffrement',
    this.statusIsManual = false,
    this.reading = 0,
    this.handsTogether = 0,
    this.memory = 0,
    this.interpretation = 0,
    this.currentTempo = 0,
    this.targetTempo = 0,
    this.measures = '',
    this.targetHours,
    this.celebratedComplete = false,
    this.emoji = '🎵',
  });
  final String id;
  String name;
  double progress;
  String goal;
  String? method;
  bool priority;
  String status; // Statut affiché / conservé
  bool statusIsManual; // false = statut déduit automatiquement des 4 étapes
  double reading;
  double handsTogether;
  double memory;
  double interpretation;
  int currentTempo;
  int targetTempo;
  String measures;
  double? targetHours; // si defini, l'avancement est calcule automatiquement depuis le temps pratique
  bool celebratedComplete; // evite de refeter le passage a 100% a chaque rebuild
  String emoji; // emoji visuel du morceau

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'progress': progress,
        'goal': goal,
        'method': method,
        'priority': priority,
        'status': status,
        'statusIsManual': statusIsManual,
        'reading': reading,
        'handsTogether': handsTogether,
        'memory': memory,
        'interpretation': interpretation,
        'currentTempo': currentTempo,
        'targetTempo': targetTempo,
        'measures': measures,
        'targetHours': targetHours,
        'celebratedComplete': celebratedComplete,
        'emoji': emoji,
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        progress: (j['progress'] as num).toDouble(),
        goal: j['goal'] as String,
        method: j['method'] as String?,
        priority: j['priority'] as bool? ?? false,
        status: _normalizeProjectStatus(j['status'] as String?),
        // Important : le statut manuel doit être restauré. Sans ce champ, un
        // morceau passé manuellement en « Répertoire d’entretien » revenait
        // en mode automatique après restauration et perdait donc son statut.
        statusIsManual: j['statusIsManual'] as bool? ?? false,
        reading: (j['reading'] as num?)?.toDouble() ?? (j['progress'] as num?)?.toDouble() ?? 0,
        handsTogether: (j['handsTogether'] as num?)?.toDouble() ?? (j['progress'] as num?)?.toDouble() ?? 0,
        memory: (j['memory'] as num?)?.toDouble() ?? (j['progress'] as num?)?.toDouble() ?? 0,
        interpretation: (j['interpretation'] as num?)?.toDouble() ?? (j['progress'] as num?)?.toDouble() ?? 0,
        currentTempo: (j['currentTempo'] as num?)?.toInt() ?? 0,
        targetTempo: (j['targetTempo'] as num?)?.toInt() ?? 0,
        measures: j['measures'] as String? ?? '',
        targetHours: (j['targetHours'] as num?)?.toDouble(),
        celebratedComplete: j['celebratedComplete'] as bool? ?? false,
        emoji: j['emoji'] as String? ?? '🎵',
      );

  String get effectiveStatus => statusIsManual
      ? status
      : statusFromStages(
          reading: reading,
          handsTogether: handsTogether,
          memory: memory,
          interpretation: interpretation,
        );

  /// Categorie dominante du morceau, deduite automatiquement de son etape la plus
  /// faible parmi les 4 curseurs — remplace l'ancien besoin de creer un "objectif"
  /// separe juste pour etiqueter un projet.
  double get weakestStageValue => [reading, handsTogether, memory, interpretation].reduce((a, b) => a < b ? a : b);

  String get weakestCategory {
    final dims = <String, double>{
      'Répertoire': reading,
      'Technique': handsTogether,
      'Mémorisation': memory,
      'Interprétation': interpretation,
    };
    var weakestCat = 'Répertoire';
    var weakestVal = dims['Répertoire']!;
    for (final e in dims.entries) {
      if (e.value < weakestVal) {
        weakestVal = e.value;
        weakestCat = e.key;
      }
    }
    return weakestCat;
  }
}

class Session {
  Session({
    required this.id,
    required this.date,
    required this.duration,
    this.projectId,
    required this.type,
    required this.rating,
    required this.notes,
    this.method,
    this.previousReading,
    this.previousHandsTogether,
    this.previousMemory,
    this.previousInterpretation,
    this.previousTempo,
    this.newTempo,
  });
  final String id;
  DateTime date;
  int duration;
  String? projectId;
  String type;
  int rating;
  String notes;
  String? method;

  // Etat des 4 etapes du morceau AVANT cette session.
  // Il permet d'annuler la session et de revenir exactement a la version precedente.
  double? previousReading;
  double? previousHandsTogether;
  double? previousMemory;
  double? previousInterpretation;

  // Tempo du morceau avant/apres cette session (BPM). previousTempo permet l'annulation
  // (comme les 4 etapes ci-dessus) ; newTempo est le point de donnee utilise pour tracer
  // la courbe de progression du tempo dans le temps. Nul si le tempo n'a pas ete renseigne
  // pour cette session (morceau sans objectif de tempo, ou champ laisse vide).
  int? previousTempo;
  int? newTempo;

  bool get hasProgressSnapshot =>
      previousReading != null &&
      previousHandsTogether != null &&
      previousMemory != null &&
      previousInterpretation != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'duration': duration,
        'projectId': projectId,
        'type': type,
        'rating': rating,
        'notes': notes,
        'method': method,
        'previousReading': previousReading,
        'previousHandsTogether': previousHandsTogether,
        'previousMemory': previousMemory,
        'previousInterpretation': previousInterpretation,
        'previousTempo': previousTempo,
        'newTempo': newTempo,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        duration: j['duration'] as int,
        projectId: j['projectId'] as String?,
        type: j['type'] as String,
        rating: j['rating'] as int,
        notes: j['notes'] as String,
        method: j['method'] as String?,
        previousReading: (j['previousReading'] as num?)?.toDouble(),
        previousHandsTogether: (j['previousHandsTogether'] as num?)?.toDouble(),
        previousMemory: (j['previousMemory'] as num?)?.toDouble(),
        previousInterpretation: (j['previousInterpretation'] as num?)?.toDouble(),
        previousTempo: (j['previousTempo'] as num?)?.toInt(),
        newTempo: (j['newTempo'] as num?)?.toInt(),
      );
}

class PlanItem {
  PlanItem({
    required this.id,
    required this.date,
    required this.duration,
    required this.title,
    required this.details,
    this.projectId,
    this.category,
    this.method,
    this.completed = false,
    List<String>? motsCles,
    this.sourceSessionId,
  }) : motsCles = motsCles ?? [];
  final String id;
  DateTime date;
  int duration;
  String title;
  String details;
  String? projectId;
  String? category;
  String? method;
  bool completed;
  List<String> motsCles; // mots-cles/tags libres pour filtrer le planning
  String? sourceSessionId; // id de la session creee quand cette entree a ete marquee terminee

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'duration': duration,
        'title': title,
        'details': details,
        'projectId': projectId,
        'category': category,
        'method': method,
        'completed': completed,
        'motsCles': motsCles,
        'sourceSessionId': sourceSessionId,
      };

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        duration: j['duration'] as int,
        title: j['title'] as String,
        details: j['details'] as String,
        projectId: j['projectId'] as String?,
        category: j['category'] as String?,
        method: j['method'] as String?,
        completed: j['completed'] as bool? ?? false,
        motsCles: (j['motsCles'] as List?)?.map((e) => e as String).toList() ?? [],
        sourceSessionId: j['sourceSessionId'] as String?,
      );
}

class RoutineItem {
  RoutineItem({
    required this.id,
    required this.label,
    this.count = 1,
    this.cadence = 'semaine', // 'jour' ou 'semaine'
    List<int>? days, // jours concernes si cadence == 'jour' (1=Lundi..7=Dimanche)
    this.fixedMinutes, // duree exacte protegee (prioritaire, prise en premier chaque jour)
    this.maxMinutes, // plafond quand la duree est calculee automatiquement (le reste va ailleurs)
    this.order = 0,
  }) : days = days ?? [1, 2, 3, 4, 5, 6, 7];
  final String id;
  String label;
  int count;
  String cadence;
  List<int> days;
  int? fixedMinutes;
  int? maxMinutes;
  int order;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'count': count,
        'cadence': cadence,
        'days': days,
        'fixedMinutes': fixedMinutes,
        'maxMinutes': maxMinutes,
        'order': order,
      };

  factory RoutineItem.fromJson(Map<String, dynamic> j) => RoutineItem(
        id: j['id'] as String,
        label: j['label'] as String,
        count: j['count'] as int? ?? 1,
        cadence: j['cadence'] as String? ?? 'semaine',
        days: (j['days'] as List?)?.map((e) => e as int).toList() ?? [1, 2, 3, 4, 5, 6, 7],
        fixedMinutes: j['fixedMinutes'] as int?,
        maxMinutes: j['maxMinutes'] as int?,
        order: j['order'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Categories (partagees entre Objectifs et Planning)
// ---------------------------------------------------------------------------

class MethodDefinition {
  MethodDefinition({required this.name, this.description = '', this.objectives = '', this.exercises = '', this.durationMinutes = 20, this.level = 'Tous niveaux'});
  String name;
  String description;
  String objectives;
  String exercises;
  int durationMinutes;
  String level;
  Map<String, dynamic> toJson() => {'name': name, 'description': description, 'objectives': objectives, 'exercises': exercises, 'durationMinutes': durationMinutes, 'level': level};
  factory MethodDefinition.fromJson(Map<String, dynamic> j) => MethodDefinition(name: j['name'] as String? ?? '', description: j['description'] as String? ?? '', objectives: j['objectives'] as String? ?? '', exercises: j['exercises'] as String? ?? '', durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 20, level: j['level'] as String? ?? 'Tous niveaux');
}

const objectiveCategories = ['Répertoire', 'Technique', 'Mémorisation', 'Interprétation', 'Lecture', 'Improvisation'];

List<String> learningMethods = ['Playground Sessions', 'MyPianoPop', 'Skoove', 'Pianoforall', 'Udemy'];
List<MethodDefinition> methodDefinitions = learningMethods.map((n) => MethodDefinition(name: n)).toList();

Color categoryColor(String? cat) {
  switch (cat) {
    case 'Répertoire':
      return const Color(0xFF3F51B5);
    case 'Technique':
      return const Color(0xFF00897B);
    case 'Mémorisation':
      return const Color(0xFFE64A19);
    case 'Interprétation':
      return const Color(0xFF8E24AA);
    case 'Lecture':
      return const Color(0xFF1976D2);
    case 'Improvisation':
      return const Color(0xFFFFA000);
    default:
      return Colors.blueGrey;
  }
}

IconData categoryIcon(String? cat) {
  switch (cat) {
    case 'Répertoire':
      return Icons.library_music;
    case 'Technique':
      return Icons.build_circle;
    case 'Mémorisation':
      return Icons.psychology;
    case 'Interprétation':
      return Icons.theater_comedy;
    case 'Lecture':
      return Icons.menu_book;
    case 'Improvisation':
      return Icons.auto_awesome;
    default:
      return Icons.music_note;
  }
}

String nextWorkRecommendation(Project p) {
  final dims = <String, double>{
    'Lecture / mains séparées': p.reading,
    'Mains ensemble': p.handsTogether,
    'Mémorisation': p.memory,
    'Interprétation': p.interpretation,
  };
  final weakest = dims.entries.reduce((a, b) => a.value <= b.value ? a : b);
  final parts = <String>[];
  if (p.measures.trim().isNotEmpty) parts.add('Mesures ${p.measures.trim()}');
  parts.add(weakest.key);
  if (p.currentTempo > 0 && p.targetTempo > 0 && p.currentTempo < p.targetTempo) {
    parts.add('${p.currentTempo} → ${p.targetTempo} BPM');
  }
  return parts.join(' · ');
}

int daysSinceLastProjectSession(Project p, List<Session> sessions) {
  DateTime? latest;
  for (final s in sessions) {
    if (s.projectId != p.id) continue;
    if (latest == null || s.date.isAfter(latest!)) latest = s.date;
  }
  if (latest == null) return -1;
  final today = DateTime.now();
  final lastDay = DateTime(latest!.year, latest!.month, latest!.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  return todayDay.difference(lastDay).inDays;
}

String reviewDueLabel(Project p, List<Session> sessions) {
  final days = daysSinceLastProjectSession(p, sessions);
  if (days < 0 || days >= 999) return 'Jamais travaillé';
  if (days >= 14) return 'À revoir maintenant · $days j';
  if (days >= 7) return 'À revoir cette semaine · $days j';
  if (days >= 4) return 'À surveiller · $days j';
  if (days == 0) return 'Vu aujourd’hui';
  return 'Vu il y a $days j';
}

String practiceBalanceLabel({required int practiced, required int target}) {
  if (target <= 0) return 'Aucune cible définie';
  final ratio = practiced / target;
  if (ratio >= 1) return 'Objectif atteint 🎯';
  if (ratio >= .8) return 'Bonne dynamique';
  if (ratio >= .5) return 'En bonne voie';
  return 'À renforcer';
}

DateTime startOfWeek(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

// ---------------------------------------------------------------------------
// App racine + persistance
// ---------------------------------------------------------------------------

class PianoPracticeApp extends StatefulWidget {
  const PianoPracticeApp({super.key});
  @override
  State<PianoPracticeApp> createState() => _PianoPracticeAppState();
}

class _PianoPracticeAppState extends State<PianoPracticeApp> {
  final navKey = GlobalKey<NavigatorState>();
  int tab = 0;
  bool loading = true;
  List<int> dailyCapacity = [30, 30, 45, 30, 30, 45, 30]; // Lundi..Dimanche, en minutes
  String weeklyInstructions = ''; // criteres de planning saisis par l'utilisateur, conserves
  List<Project> projects = [];
  List<Session> sessions = [];
  List<PlanItem> plan = [];
  List<RoutineItem> routine = [];
  List<Challenge> challenges = [];
  bool darkMode = false;
  int bestStreakEver = 0;
  List<String> seenBadgeIds = [];

  int get weeklyTarget => dailyCapacity.fold(0, (a, b) => a + b);

  /// Nombre de jours consecutifs (jusqu'a aujourd'hui) avec au moins une session
  /// pratiquee. Si rien n'a encore ete pratique aujourd'hui, la serie reste "en vie"
  /// tant qu'hier comptait une session — elle ne casse qu'apres un jour complet sans rien.
  int get practiceStreak {
    final days = sessions.map((s) => DateTime(s.date.year, s.date.month, s.date.day)).toSet();
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Analyse tes vraies donnees (sessions, morceaux, categories) pour surfacer des
  /// suggestions concretes — pas une IA, des regles simples appliquees a l'historique reel.
  List<Suggestion> get practiceSuggestions {
    final suggestions = <Suggestion>[];
    final now = DateTime.now();

    DateTime? lastSessionOf(String projectId) {
      DateTime? latest;
      for (final s in sessions.where((s) => s.projectId == projectId)) {
        if (latest == null || s.date.isAfter(latest)) latest = s.date;
      }
      return latest;
    }

    // 1) Morceaux actifs pas travailles depuis un moment.
    for (final p in projects.where((p) => p.effectiveStatus != 'Répertoire d’entretien' && p.progress < 1)) {
      final last = lastSessionOf(p.id);
      if (last == null) continue; // jamais commence : pas encore "neglige", on evite le bruit
      final daysSince = now.difference(last).inDays;
      if (daysSince >= 7) {
        suggestions.add(Suggestion(
          Icons.schedule,
          '${p.name} n\'a pas été travaillé depuis $daysSince jours.',
          instruction: 'priorité ${p.name}',
          color: Colors.orange,
        ));
      }
    }

    // 2) Morceaux du répertoire d’entretien pas revus depuis longtemps.
    final staleReview = projects.where((p) => p.effectiveStatus == 'Répertoire d’entretien').where((p) {
      final last = lastSessionOf(p.id);
      return last != null && now.difference(last).inDays >= 14;
    }).toList();
    if (staleReview.isNotEmpty) {
      final names = staleReview.map((p) => p.name).join(', ');
      final plural = staleReview.length > 1;
      suggestions.add(Suggestion(
        Icons.refresh,
        '${plural ? "Ces morceaux n'ont" : "Ce morceau n'a"} pas été révisé${plural ? 's' : ''} depuis 2 semaines ou plus : $names',
        instruction: 'priorité à réviser : $names',
        color: Colors.teal,
      ));
    }

    final since = now.subtract(const Duration(days: 21));
    final recentSessions = sessions.where((s) => s.date.isAfter(since)).toList();
    final recentTotal = recentSessions.fold(0, (a, s) => a + s.duration);

    // 3) Categorie nettement delaissee sur les 3 dernieres semaines.
    if (recentSessions.length >= 4 && recentTotal > 0) {
      final byType = <String, int>{};
      for (final s in recentSessions) {
        byType[s.type] = (byType[s.type] ?? 0) + s.duration;
      }
      for (final cat in objectiveCategories) {
        final catMin = byType[cat] ?? 0;
        if (catMin / recentTotal < 0.05) {
          suggestions.add(Suggestion(
            Icons.balance,
            'La catégorie "$cat" est nettement moins pratiquée que les autres ces 3 dernières semaines.',
            instruction: 'priorité $cat',
            color: Colors.deepPurple,
          ));
        }
      }
    }

    // 4) Projets prioritaires delaisses.
    final priorityIds = projects.where((p) => p.priority && p.effectiveStatus != 'Répertoire d’entretien' && p.progress < 1).map((p) => p.id).toSet();
    if (priorityIds.isNotEmpty && recentTotal > 0) {
      final priorityMin = recentSessions.where((s) => priorityIds.contains(s.projectId)).fold(0, (a, s) => a + s.duration);
      if (priorityMin / recentTotal < 0.2) {
        suggestions.add(Suggestion(
          Icons.star_outline,
          'Tu consacres peu de temps à tes morceaux prioritaires ces 3 dernières semaines.',
          instruction: 'priorité morceaux prioritaires',
          color: Colors.amber.shade800,
        ));
      }
    }

    // 5) Objectif d'heures presque atteint.
    for (final p in projects.where((p) => p.targetHours != null && p.progress < 1)) {
      final totalMinutes = sessions.where((s) => s.projectId == p.id).fold(0, (a, s) => a + s.duration);
      final remainingHours = p.targetHours! - (totalMinutes / 60);
      if (remainingHours > 0 && remainingHours <= p.targetHours! * 0.15) {
        suggestions.add(Suggestion(
          Icons.flag_outlined,
          '${p.name} approche de son objectif — encore environ ${remainingHours.toStringAsFixed(1)} h.',
          instruction: 'priorité ${p.name}',
          color: Colors.green,
        ));
      }
    }

    // 6) Ressenti en baisse sur un morceau precis (signal de plateau ou de frustration).
    // Compare la moyenne des 3 dernieres sessions du morceau a celle des 3 precedentes :
    // il faut a la fois une vraie baisse (pas un simple mauvais jour isole) et un ressenti
    // recent effectivement moyen/bas, pour eviter de signaler une chute de 5 a 4.2.
    // Instruction par defaut "moins X" : lever le pied est le choix le moins risque quand on
    // ne sait pas si c'est de la fatigue ou un vrai blocage — ce n'est qu'une proposition,
    // l'utilisateur reste libre de ne pas l'appliquer.
    for (final p in projects.where((p) => p.effectiveStatus != 'Répertoire d’entretien' && p.progress < 1)) {
      final projectSessions = sessions.where((s) => s.projectId == p.id).toList()..sort((a, b) => a.date.compareTo(b.date));
      if (projectSessions.length < 6) continue;
      final recent = projectSessions.sublist(projectSessions.length - 3);
      final older = projectSessions.sublist(projectSessions.length - 6, projectSessions.length - 3);
      final recentAvg = recent.fold(0, (a, s) => a + s.rating) / recent.length;
      final olderAvg = older.fold(0, (a, s) => a + s.rating) / older.length;
      if (recentAvg <= olderAvg - 0.75 && recentAvg <= 3) {
        suggestions.add(Suggestion(
          Icons.sentiment_dissatisfied,
          'Le ressenti sur ${p.name} baisse depuis quelques sessions (${olderAvg.toStringAsFixed(1)} → ${recentAvg.toStringAsFixed(1)} ★). '
          'Ça peut valoir le coup de changer d’angle ou de lever le pied dessus un moment.',
          instruction: 'moins ${p.name}',
          color: Colors.blueGrey,
        ));
      }
    }

    return suggestions;
  }

  /// Bilan d'une semaine donnee (identifiee par son lundi [weekStart]), calcule a partir
  /// des vraies sessions loguees : temps total, morceaux travailles, meilleur jour, jours
  /// pratiques, ressenti moyen (moyenne des notes de session). Reutilisable pour la semaine
  /// en cours comme pour n'importe quelle semaine passee (voir [weeklyHistory]).
  WeeklyBilan weeklyBilanFor(DateTime weekStart) {
    final start = startOfWeek(weekStart);
    final end = start.add(const Duration(days: 7));
    final weekSessions = sessions.where((s) => !s.date.isBefore(start) && s.date.isBefore(end)).toList();

    final totalMinutes = weekSessions.fold(0, (a, s) => a + s.duration);

    final byProject = <String, int>{};
    for (final s in weekSessions) {
      if (s.projectId == null) continue;
      byProject[s.projectId!] = (byProject[s.projectId!] ?? 0) + s.duration;
    }
    final pieces = byProject.entries
        .map((e) => MapEntry(projectById(e.key), e.value))
        .where((e) => e.key != null)
        .map((e) => MapEntry(e.key!, e.value))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byDay = <DateTime, int>{};
    for (final s in weekSessions) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      byDay[d] = (byDay[d] ?? 0) + s.duration;
    }
    DateTime? bestDay;
    var bestDayMinutes = 0;
    byDay.forEach((d, m) {
      if (m > bestDayMinutes) {
        bestDayMinutes = m;
        bestDay = d;
      }
    });

    final avgRating = weekSessions.isEmpty ? null : weekSessions.fold(0, (a, s) => a + s.rating) / weekSessions.length;

    return WeeklyBilan(
      weekStart: start,
      totalMinutes: totalMinutes,
      pieces: pieces,
      bestDay: bestDay,
      bestDayMinutes: bestDayMinutes,
      daysPracticed: byDay.length,
      avgRating: avgRating,
    );
  }

  /// Bilan de la semaine en cours — conserve pour compatibilite avec le reste de l'app.
  WeeklyBilan get weeklyBilan => weeklyBilanFor(DateTime.now());

  /// Historique des [weeks] dernieres semaines (la semaine en cours incluse), du plus
  /// ancien au plus recent. Si la pratique enregistree est plus jeune que [weeks]
  /// semaines, la liste est raccourcie a la premiere semaine ayant une session plutot que
  /// d'afficher une longue serie de semaines vides avant le debut de l'usage de l'app.
  List<WeeklyBilan> weeklyHistory({int weeks = 12}) {
    final currentStart = startOfWeek(DateTime.now());
    DateTime? earliest;
    for (final s in sessions) {
      if (earliest == null || s.date.isBefore(earliest)) earliest = s.date;
    }
    var available = weeks;
    if (earliest != null) {
      final earliestStart = startOfWeek(earliest);
      final weeksSinceStart = currentStart.difference(earliestStart).inDays ~/ 7 + 1;
      available = weeksSinceStart < weeks ? weeksSinceStart : weeks;
    } else {
      available = 1;
    }
    if (available < 1) available = 1;
    return List.generate(available, (i) {
      final start = currentStart.subtract(Duration(days: 7 * (available - 1 - i)));
      return weeklyBilanFor(start);
    });
  }

  void openBilanScreen() {
    Navigator.of(navKey.currentContext!).push(MaterialPageRoute(
      builder: (_) => BilanScreen(
        currentBilan: weeklyBilan,
        weeklyHistory: weeklyHistory,
        onFocusNextWeek: (cat) {
          final current = weeklyInstructions.trim();
          setState(() {
            weeklyInstructions = current.isEmpty ? 'priorité $cat' : '$current, priorité $cat';
          });
          _persist();
        },
      ),
    ));
  }

  void orientSuggestion(String instruction) {
    final next = instruction.trim();
    if (next.isEmpty) return;
    final current = weeklyInstructions.trim();
    if (_fold(current).contains(_fold(next))) return;
    setState(() {
      weeklyInstructions = current.isEmpty ? next : '$current, $next';
    });
    _persist();
  }

  /// Ajoute une consigne puis propose de regenerer le planning de la semaine en cours.
  /// Les seances deja realisees restent conservees par [proposeWeeklyPlan].
  Future<void> orientSuggestionThisWeek(String instruction) async {
    final next = instruction.trim();
    if (next.isEmpty) return;
    final current = weeklyInstructions.trim();
    final combined = _fold(current).contains(_fold(next))
        ? current
        : (current.isEmpty ? next : '$current, $next');

    // Application directe : pas de passage par « Proposer un planning ».
    // Une seule confirmation courte protège le planning existant ; les séances
    // déjà réalisées restent conservées.
    final apply = await showDialog<bool>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        title: const Text('Appliquer maintenant ?'),
        content: const Text(
          'Le planning de cette semaine sera régénéré avec cette priorité. Les séances déjà faites seront conservées.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Appliquer')),
        ],
      ),
    );
    if (apply != true) return;

    if (combined != weeklyInstructions) {
      setState(() => weeklyInstructions = combined);
      await _persist();
    }
    await proposeWeeklyPlan(skipInstructionsDialog: true);
  }

  List<Challenge> get thisWeekChallenges {
    final start = startOfWeek(DateTime.now());
    return challenges.where((c) => c.weekStart == start).toList();
  }

  /// Progression actuelle d'un defi, calculee en direct depuis les sessions de sa semaine
  /// (jamais stockee, toujours a jour).
  int challengeProgress(Challenge ch) {
    final weekEnd = ch.weekStart.add(const Duration(days: 7));
    final weekSessions = sessions.where((s) => !s.date.isBefore(ch.weekStart) && s.date.isBefore(weekEnd));
    switch (ch.type) {
      case 'days':
        return weekSessions.map((s) => DateTime(s.date.year, s.date.month, s.date.day)).toSet().length;
      case 'category':
        return weekSessions.where((s) => s.type == ch.refId).fold(0, (a, s) => a + s.duration);
      case 'project':
        return weekSessions.any((s) => s.projectId == ch.refId) ? 1 : 0;
      default:
        return 0;
    }
  }

  /// Genere 2-3 defis pour la semaine en cours si aucun n'existe encore pour elle, a
  /// partir de ton rythme recent (jours pratiques), d'une categorie delaissee et d'un
  /// morceau actif non travaille depuis un moment. Rien n'est genere au hasard.
  void _ensureWeeklyChallenges() {
    final weekStart = startOfWeek(DateTime.now());
    if (challenges.any((c) => c.weekStart == weekStart)) return;

    final generated = <Challenge>[];
    final now = DateTime.now();

    // 1) Defi "jours pratiques" : rythme recent + 1, entre 3 et 7.
    final since7 = now.subtract(const Duration(days: 7));
    final recentDays = sessions
        .where((s) => s.date.isAfter(since7))
        .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
        .toSet()
        .length;
    final daysTarget = (recentDays + 1).clamp(3, 7);
    generated.add(Challenge(
      id: newId(),
      type: 'days',
      description: 'Pratiquer $daysTarget jours cette semaine',
      target: daysTarget,
      weekStart: weekStart,
    ));

    // 2) Défi catégorie délaissée : moins de 15 % du temps sur les 21 derniers jours.
    final since21 = now.subtract(const Duration(days: 21));
    final recent21 = sessions.where((s) => s.date.isAfter(since21)).toList();
    if (recent21.isNotEmpty) {
      final byType = <String, int>{};
      for (final s in recent21) {
        byType[s.type] = (byType[s.type] ?? 0) + s.duration;
      }
      final total21 = byType.values.fold(0, (a, b) => a + b);
      String? weakest;
      var weakestShare = 1.0;
      for (final cat in objectiveCategories) {
        final share = total21 > 0 ? (byType[cat] ?? 0) / total21 : 0.0;
        if (share < weakestShare) {
          weakestShare = share;
          weakest = cat;
        }
      }
      if (weakest != null && weakestShare < 0.15) {
        generated.add(Challenge(
          id: newId(),
          type: 'category',
          description: 'Consacrer 15 min à "$weakest" cette semaine',
          target: 15,
          refId: weakest,
          weekStart: weekStart,
        ));
      }
    }

    // 3) Defi morceau actif le plus delaisse (au moins 5 jours sans session).
    Project? mostNeglected;
    var maxDaysSince = -1;
    for (final p in projects.where((p) => p.effectiveStatus != 'Répertoire d’entretien' && p.progress < 1)) {
      DateTime? last;
      for (final s in sessions.where((s) => s.projectId == p.id)) {
        if (last == null || s.date.isAfter(last)) last = s.date;
      }
      if (last == null) continue;
      final daysSince = now.difference(last).inDays;
      if (daysSince > maxDaysSince) {
        maxDaysSince = daysSince;
        mostNeglected = p;
      }
    }
    if (mostNeglected != null && maxDaysSince >= 5) {
      generated.add(Challenge(
        id: newId(),
        type: 'project',
        description: 'Travailler sur "${mostNeglected.name}" cette semaine',
        target: 1,
        refId: mostNeglected.id,
        weekStart: weekStart,
      ));
    }

    if (generated.isNotEmpty) {
      challenges.addAll(generated);
      _persist();
    }
  }

  Future<void> _showCelebration({required String emoji, required String title, required String message}) async {
    await showDialog<void>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [Center(child: FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Super !')))],
      ),
    );
  }

  /// A appeler apres toute action pouvant faire progresser un defi ou un morceau, pour
  /// feter le moment ou une cible vient d'etre atteinte (une seule fois chacune, grace a
  /// [Challenge.celebrated]/[Project.celebratedComplete]).
  /// Badges debloques a partir de vraies etapes (series, heures cumulees, morceaux
  /// termines, defis relevees, sessions loguees) — recalcule en direct, jamais stocke
  /// comme tel (seul [bestStreakEver] a besoin d'etre memorise, la serie courante
  /// pouvant redescendre a zero).
  List<AppBadge> get badges {
    final totalMinutesAllTime = sessions.fold(0, (a, s) => a + s.duration);
    final totalSessions = sessions.length;
    final completedPieces = projects.where((p) => p.progress >= 1).length;
    final challengesWon = challenges.where((c) => c.celebrated).length;
    final byProject = <String, int>{};
    for (final s in sessions) {
      if (s.projectId == null) continue;
      byProject[s.projectId!] = (byProject[s.projectId!] ?? 0) + s.duration;
    }
    final maxSingleProjectMinutes = byProject.values.isEmpty ? 0 : byProject.values.reduce((a, b) => a > b ? a : b);

    return [
      AppBadge('streak3', '🔥', '3 jours d\'affilée', 'Pratiquer 3 jours de suite', bestStreakEver >= 3),
      AppBadge('streak7', '🔥', '7 jours d\'affilée', 'Une semaine complète sans interruption', bestStreakEver >= 7),
      AppBadge('streak14', '🔥', '14 jours d\'affilée', 'Deux semaines de suite', bestStreakEver >= 14),
      AppBadge('streak30', '🔥', '30 jours d\'affilée', 'Un mois complet sans interruption', bestStreakEver >= 30),
      AppBadge('hours5', '⏱️', '5 h de pratique', 'Cumuler 5 heures de pratique au total', totalMinutesAllTime >= 300),
      AppBadge('hours20', '⏱️', '20 h de pratique', 'Cumuler 20 heures de pratique au total', totalMinutesAllTime >= 1200),
      AppBadge('hours50', '⏱️', '50 h de pratique', 'Cumuler 50 heures de pratique au total', totalMinutesAllTime >= 3000),
      AppBadge('hours100', '⏱️', '100 h de pratique', 'Cumuler 100 heures de pratique au total', totalMinutesAllTime >= 6000),
      AppBadge('piece1', '🎉', 'Premier morceau terminé', 'Amener un morceau à 100 %', completedPieces >= 1),
      AppBadge('piece5', '🏆', '5 morceaux terminés', 'Amener 5 morceaux à 100 %', completedPieces >= 5),
      AppBadge('deep10', '🎹', '10 h sur un seul morceau', 'Approfondir un morceau en profondeur', maxSingleProjectMinutes >= 600),
      AppBadge('challenge1', '🎯', 'Premier défi relevé', 'Réussir un défi hebdomadaire', challengesWon >= 1),
      AppBadge('challenge5', '🎯', '5 défis relevés', 'Réussir 5 défis hebdomadaires', challengesWon >= 5),
      AppBadge('sessions10', '📈', '10 sessions loguées', 'Enregistrer 10 séances de pratique', totalSessions >= 10),
      AppBadge('sessions50', '📈', '50 sessions loguées', 'Enregistrer 50 séances de pratique', totalSessions >= 50),
    ];
  }

  void openBadgesScreen() {
    Navigator.of(navKey.currentContext!).push(MaterialPageRoute(builder: (_) => BadgesScreen(badges: badges)));
  }

  void _checkCelebrations() {
    var changed = false;
    if (practiceStreak > bestStreakEver) {
      bestStreakEver = practiceStreak;
      changed = true;
    }
    for (final ch in thisWeekChallenges) {
      if (!ch.celebrated && challengeProgress(ch) >= ch.target) {
        ch.celebrated = true;
        changed = true;
        _showCelebration(emoji: '🎯', title: 'Défi relevé !', message: ch.description);
      }
    }
    for (final p in projects) {
      if (!p.celebratedComplete && p.progress >= 1) {
        p.celebratedComplete = true;
        changed = true;
        _showCelebration(emoji: '🎉', title: 'Morceau terminé !', message: '${p.name} est maintenant à 100 % !');
      }
    }
    for (final b in badges) {
      if (b.earned && !seenBadgeIds.contains(b.id)) {
        seenBadgeIds.add(b.id);
        changed = true;
        _showCelebration(emoji: b.emoji, title: 'Badge débloqué !', message: b.title);
      }
    }
    if (changed) _persist();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCapacity = prefs.getString('dailyCapacity');
    if (rawCapacity != null) {
      dailyCapacity = (jsonDecode(rawCapacity) as List).map((e) => e as int).toList();
    }
    weeklyInstructions = prefs.getString('weeklyInstructions') ?? '';
    final rawMethods = prefs.getString('learningMethods');
    if (rawMethods != null) {
      learningMethods = (jsonDecode(rawMethods) as List).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toSet().toList();
    }
    final rawMethodDefinitions = prefs.getString('methodDefinitions');
    if (rawMethodDefinitions != null) {
      methodDefinitions = (jsonDecode(rawMethodDefinitions) as List).map((e) => MethodDefinition.fromJson(Map<String, dynamic>.from(e as Map))).where((m) => m.name.trim().isNotEmpty).toList();
    } else {
      methodDefinitions = learningMethods.map((n) => MethodDefinition(name: n)).toList();
    }
    for (final name in learningMethods) {
      if (!methodDefinitions.any((m) => m.name.toLowerCase() == name.toLowerCase())) methodDefinitions.add(MethodDefinition(name: name));
    }
    darkMode = prefs.getBool('darkMode') ?? false;
    bestStreakEver = prefs.getInt('bestStreakEver') ?? 0;
    seenBadgeIds = (jsonDecode(prefs.getString('seenBadgeIds') ?? '[]') as List).map((e) => e as String).toList();
    final rawProjects = prefs.getString('projects');
    if (rawProjects == null) {
      _seedDemoData();
      await _persist();
    } else {
      projects = (jsonDecode(rawProjects) as List).map((e) => Project.fromJson(e)).toList();
      sessions = (jsonDecode(prefs.getString('sessions') ?? '[]') as List).map((e) => Session.fromJson(e)).toList();
      plan = (jsonDecode(prefs.getString('plan') ?? '[]') as List).map((e) => PlanItem.fromJson(e)).toList();
      routine =
          (jsonDecode(prefs.getString('routine') ?? '[]') as List).map((e) => RoutineItem.fromJson(e)).toList();
      challenges =
          (jsonDecode(prefs.getString('challenges') ?? '[]') as List).map((e) => Challenge.fromJson(e)).toList();
    }
    _syncMethodsFromUsage();
    _ensureWeeklyChallenges();
    if (mounted) setState(() => loading = false);
  }

  void _seedDemoData() {
    final p = Project(id: newId(), name: 'Sonate au clair de lune', emoji: '🌙', progress: .65, goal: 'Jouer le mouvement entier par cœur à 100 BPM', priority: true, reading: .75, handsTogether: .65, memory: .55, interpretation: .65, currentTempo: 80, targetTempo: 100, measures: '25–48');
    final r = Project(id: newId(), name: 'River Flows in You', emoji: '💧', progress: .35, goal: 'Jouer le morceau avec régularité et fluidité', reading: .45, handsTogether: .35, memory: .25, interpretation: .35, currentTempo: 60, targetTempo: 90, measures: '1–32');
    final e = Project(id: newId(), name: 'The Entertainer', emoji: '🎩', progress: .25, goal: 'Jouer le morceau avec rythme et articulation', reading: .35, handsTogether: .25, memory: .20, interpretation: .20, currentTempo: 70, targetTempo: 110, measures: '1–24');
    final t = Project(id: newId(), name: 'MyPianoPop — parcours', emoji: '🎹', progress: .45, goal: 'Avancer régulièrement dans le parcours puis passer au niveau intermédiaire', method: 'MyPianoPop', reading: .55, handsTogether: .45, memory: .40, interpretation: .40);
    projects = [p, r, e, t];
    sessions = [
      Session(id: newId(), date: DateTime.now().subtract(const Duration(days: 1)), duration: 42, projectId: p.id, type: 'Répertoire', rating: 4, notes: 'Travail des transitions, encore quelques hésitations.'),
      Session(id: newId(), date: DateTime.now().subtract(const Duration(days: 2)), duration: 30, projectId: p.id, type: 'Lecture', rating: 3, notes: 'Mesures 1-24'),
      Session(id: newId(), date: DateTime.now().subtract(const Duration(days: 3)), duration: 45, projectId: t.id, type: 'Technique', rating: 5, notes: 'Gammes majeures, régularité et précision.'),
    ];
    final d = DateTime.now();
    DateTime day(int n) => DateTime(d.year, d.month, d.day + n);
    plan = [
      PlanItem(id: newId(), date: day(-2), duration: 45, title: 'Technique - gammes', details: 'Fluidité et précision', projectId: t.id, category: 'Technique', completed: true),
      PlanItem(id: newId(), date: day(-1), duration: 30, title: 'Sonate', details: 'Mesures 1-24', projectId: p.id, category: 'Répertoire', completed: true),
      PlanItem(id: newId(), date: day(0), duration: 45, title: 'Sonate', details: 'Mesures 25-48 - Tempo 80 → 90 BPM', projectId: p.id, category: 'Répertoire'),
      PlanItem(id: newId(), date: day(1), duration: 30, title: 'Improvisation jazz', details: 'Explorer le mode dorien'),
      PlanItem(id: newId(), date: day(2), duration: 0, title: 'Repos', details: 'Prends le temps de récupérer'),
      PlanItem(id: newId(), date: day(3), duration: 60, title: 'Répétition complète', details: 'Jouer le mouvement en entier', projectId: p.id, category: 'Répertoire'),
      PlanItem(id: newId(), date: day(4), duration: 30, title: 'Bilan + pratique libre', details: "Analyse et points d'amélioration"),
    ];
    routine = [
      RoutineItem(
        id: newId(),
        label: 'Mini-révision hebdomadaire',
        count: 1,
        cadence: 'jour',
        days: const [7],
        fixedMinutes: 20,
        order: 0,
      ),
    ];
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dailyCapacity', jsonEncode(dailyCapacity));
    await prefs.setString('weeklyInstructions', weeklyInstructions);
    await prefs.setString('learningMethods', jsonEncode(learningMethods));
    await prefs.setString('methodDefinitions', jsonEncode(methodDefinitions.map((e) => e.toJson()).toList()));
    await prefs.setBool('darkMode', darkMode);
    await prefs.setInt('bestStreakEver', bestStreakEver);
    await prefs.setString('seenBadgeIds', jsonEncode(seenBadgeIds));
    await prefs.setString('projects', jsonEncode(projects.map((e) => e.toJson()).toList()));
    await prefs.setString('sessions', jsonEncode(sessions.map((e) => e.toJson()).toList()));
    await prefs.setString('plan', jsonEncode(plan.map((e) => e.toJson()).toList()));
    await prefs.setString('routine', jsonEncode(routine.map((e) => e.toJson()).toList()));
    await prefs.setString('challenges', jsonEncode(challenges.map((e) => e.toJson()).toList()));
  }

  /// Garde la liste des méthodes synchronisée avec les méthodes réellement utilisées.
  /// Cela récupère notamment les anciennes données/imports où un projet, une session
  /// ou une séance du planning référence une méthode absente de la liste.
  void _syncMethodsFromUsage() {
    final names = <String>{
      ...learningMethods.where((m) => m.trim().isNotEmpty),
      ...methodDefinitions.map((m) => m.name).where((m) => m.trim().isNotEmpty),
      ...projects.map((p) => p.method).whereType<String>().where((m) => m.trim().isNotEmpty),
      ...sessions.map((s) => s.method).whereType<String>().where((m) => m.trim().isNotEmpty),
      ...plan.map((x) => x.method).whereType<String>().where((m) => m.trim().isNotEmpty),
    };

    for (final name in names) {
      if (!methodDefinitions.any((m) => m.name.toLowerCase() == name.toLowerCase())) {
        methodDefinitions.add(MethodDefinition(name: name));
      }
    }
    learningMethods = methodDefinitions.map((m) => m.name).toList();
  }

  Project? projectById(String? id) => id == null ? null : projects.where((p) => p.id == id).firstOrNull;


  /// Telecharge un fichier .json contenant toutes les donnees de l'application (sauvegarde).
  void exportData() {
    final data = {
      'dailyCapacity': dailyCapacity,
      'weeklyInstructions': weeklyInstructions,
      'learningMethods': learningMethods,
      'methodDefinitions': methodDefinitions.map((e) => e.toJson()).toList(),
      'darkMode': darkMode,
      'bestStreakEver': bestStreakEver,
      'seenBadgeIds': seenBadgeIds,
      'projects': projects.map((e) => e.toJson()).toList(),
      'sessions': sessions.map((e) => e.toJson()).toList(),
      'plan': plan.map((e) => e.toJson()).toList(),
      'routine': routine.map((e) => e.toJson()).toList(),
      'challenges': challenges.map((e) => e.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
    };
    final bytes = utf8.encode(jsonEncode(data));
    final blob = html.Blob([bytes], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    html.AnchorElement(href: url)
      ..setAttribute('download', 'piano_practice_backup_$dateStr.json')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// Restaure les donnees a partir d'un fichier .json exporte precedemment. Remplace TOUT
  /// ce qui existe actuellement dans l'application, apres confirmation.
  Future<void> importData() async {
    final input = html.FileUploadInputElement()..accept = '.json,application/json';
    input.click();
    await input.onChange.first;
    final files = input.files;
    if (files == null || files.isEmpty) return;

    final reader = html.FileReader();
    reader.readAsText(files[0]);
    await reader.onLoad.first;
    final content = reader.result as String;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(content) as Map<String, dynamic>;
      // Verifications minimales pour s'assurer que c'est bien un fichier de sauvegarde valide.
      if (!data.containsKey('projects') || !data.containsKey('sessions')) {
        throw const FormatException('structure inattendue');
      }
    } catch (e) {
      await showDialog<void>(
        context: navKey.currentContext!,
        builder: (c) => AlertDialog(
          title: const Text('Fichier invalide'),
          content: const Text('Ce fichier ne semble pas etre une sauvegarde valide de Piano Practice.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: const Text(
          'Toutes les donnees actuelles (morceaux, sessions, routine, planning) seront remplacees. Avant de continuer, il est recommande de creer une sauvegarde de securite.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              exportData();
              Navigator.pop(c, false);
            },
            child: const Text('Sauvegarder puis annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      setState(() {
        dailyCapacity = ((data['dailyCapacity'] as List?) ?? [30, 30, 45, 30, 30, 45, 30]).map((e) => e as int).toList();
        weeklyInstructions = data['weeklyInstructions'] as String? ?? '';
        if (data['learningMethods'] is List) {
          learningMethods = (data['learningMethods'] as List).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toSet().toList();
        }
        darkMode = data['darkMode'] as bool? ?? false;
        bestStreakEver = data['bestStreakEver'] as int? ?? 0;
        seenBadgeIds = ((data['seenBadgeIds'] as List?) ?? []).map((e) => e as String).toList();
        projects = ((data['projects'] as List?) ?? []).map((e) => Project.fromJson(e)).toList();
        sessions = ((data['sessions'] as List?) ?? []).map((e) => Session.fromJson(e)).toList();
        plan = ((data['plan'] as List?) ?? []).map((e) => PlanItem.fromJson(e)).toList();
        routine = ((data['routine'] as List?) ?? []).map((e) => RoutineItem.fromJson(e)).toList();
        challenges = ((data['challenges'] as List?) ?? []).map((e) => Challenge.fromJson(e)).toList();
      });
      await _persist();
      await showDialog<void>(
        context: navKey.currentContext!,
        builder: (c) => AlertDialog(
          title: const Text('Sauvegarde restaurée'),
          content: const Text('Tes données ont bien été restaurées.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
        ),
      );
    } catch (e) {
      await showDialog<void>(
        context: navKey.currentContext!,
        builder: (c) => AlertDialog(
          title: const Text('Erreur pendant la restauration'),
          content: Text('Le fichier contient des données mal formées : $e'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
        ),
      );
    }
  }

  /// Minutes reellement pratiquees (sessions loguees) depuis le debut de la semaine en cours.
  int get minutes {
    final start = startOfWeek(DateTime.now());
    return sessions.where((s) => !s.date.isBefore(start)).fold(0, (a, s) => a + s.duration);
  }

  static const _reviewShareCap = 0.3; // au plus 30% du temps hebdo pour la revision
  static const _reviewMinutesPerPiece = 20; // temps de revision souhaite par morceau/semaine

  /// Repartition recommandee du temps hebdomadaire par PROJET (morceau) : les morceaux
  /// "À réviser" recoivent un budget de revision reserve (plafonne a 30% du temps hebdo),
  /// le reste va aux morceaux "En cours" actifs (avancement < 100%) au prorata de ce qu'il
  /// leur reste a apprendre. Les projets marques "priorite" recoivent un poids supplementaire.
  /// [multipliers] permet d'ajuster ponctuellement le poids d'un projet (ex: consignes
  /// specifiques du moment) sans toucher a ses donnees persistees ; un multiplicateur de 0
  /// exclut le projet de cette generation.
  Map<String, int> recommendedMinutesByProject({Map<String, double>? multipliers}) {
    final review = projects.where((p) => p.effectiveStatus == 'Répertoire d’entretien').toList();
    final active = projects.where((p) => p.effectiveStatus != 'Répertoire d’entretien' && p.progress < 1).toList();
    if (review.isEmpty && active.isEmpty) return {};

    final result = <String, int>{};

    var reviewBudget = 0;
    if (review.isNotEmpty) {
      final desired = review.length * _reviewMinutesPerPiece;
      final normalCap = (weeklyTarget * _reviewShareCap).round();

      // Une consigne de priorité sélectionne les morceaux concernés, mais ne
      // multiplie pas leur durée individuelle. Une révision standard reste de
      // 20 min par morceau : la priorité doit surtout garantir leur présence
      // dans le planning, pas transformer automatiquement 20 min en 50 min.
      final perPiece = review.isEmpty ? 0 : reviewBudget ~/ review.length;
      final effectivePerPiece = perPiece > 0 ? perPiece : (weeklyTarget > 0 ? 1 : 0);

      if (effectivePerPiece > 0) {
        for (final p in review) {
          final m = multipliers?[p.id] ?? 1.0;
          if (m <= 0) continue;
          result[p.id] = effectivePerPiece;
        }
      }
    }

    final remainingBudget = weeklyTarget - reviewBudget;
    if (active.isNotEmpty && remainingBudget > 0) {
      final weightById = <String, double>{};
      final now = DateTime.now();
      DateTime? lastSessionOf(String projectId) {
        DateTime? latest;
        for (final s in sessions.where((s) => s.projectId == projectId)) {
          if (latest == null || s.date.isAfter(latest!)) latest = s.date;
        }
        return latest;
      }
      for (final p in active) {
        final m = multipliers?[p.id] ?? 1.0;
        if (m <= 0) continue;
        // V10 : le générateur tient aussi compte de la fréquence de contact.
        // Un morceau peu travaillé récemment reçoit un bonus, sans écraser
        // l'avancement ni la priorité.
        final last = lastSessionOf(p.id);
        final daysSince = last == null ? 999 : now.difference(last).inDays;
        final recencyBonus = daysSince >= 14 ? 1.65 : (daysSince >= 7 ? 1.35 : (daysSince >= 3 ? 1.12 : 1.0));
        final stageBonus = 1.0 + (1.0 - p.weakestStageValue) * .35;
        weightById[p.id] = (1 - p.progress) * (p.priority ? 1.75 : 1) * recencyBonus * stageBonus * m;
      }
      final totalWeight = weightById.values.fold<double>(0, (a, b) => a + b);
      if (totalWeight > 0) {
        for (final e in weightById.entries) {
          result[e.key] = (remainingBudget * e.value / totalWeight).round();
        }
      }
    }

    return result;
  }

  /// Meme repartition, agregee par categorie (deduite automatiquement de l'etape la plus
  /// faible de chaque projet) pour les besoins d'affichage/comparaison.
  Map<String, int> get recommendedMinutesByCategory {
    final byProject = recommendedMinutesByProject();
    if (byProject.isEmpty) return {};
    final map = <String, int>{};
    byProject.forEach((projectId, mins) {
      final cat = projectById(projectId)?.weakestCategory ?? 'Répertoire';
      map[cat] = (map[cat] ?? 0) + mins;
    });
    return map;
  }

  /// Minutes deja planifiees cette semaine, regroupees par categorie.
  /// Note : 'Lecture' et 'Improvisation' restent des categories a part entiere
  /// partout ailleurs (tag, couleur, icone), mais le moteur de recommandation
  /// ne raisonne qu'en 4 categories (issues de Project.weakestCategory). On les
  /// rattache donc ici a leur categorie de recommandation la plus proche
  /// ('Lecture' -> 'Répertoire', 'Improvisation' -> 'Technique') pour que la
  /// comparaison recommande/planifie reste juste, sans jamais afficher une
  /// cible a 0 min pour ces deux categories.
  Map<String, int> get plannedMinutesByCategory {
    final start = startOfWeek(DateTime.now());
    final end = start.add(const Duration(days: 7));
    const mergeForComparison = {'Lecture': 'Répertoire', 'Improvisation': 'Technique'};
    final map = <String, int>{};
    for (final x in plan) {
      if (x.date.isBefore(start) || !x.date.isBefore(end)) continue;
      final cat = mergeForComparison[x.category] ?? x.category ?? 'Non catégorisé';
      map[cat] = (map[cat] ?? 0) + x.duration;
    }
    return map;
  }

  static const _weekdayLabels = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

  Future<void> editDailyCapacity() async {
    final values = [...dailyCapacity];
    final r = await showDialog<List<int>>(
      context: navKey.currentContext!,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final total = values.fold<int>(0, (a, b) => a + b);
          return AlertDialog(
            title: const Text('Disponibilité par jour'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 7; i++)
                    Row(children: [
                      SizedBox(width: 84, child: Text(_weekdayLabels[i])),
                      Expanded(
                        child: Slider(
                          value: values[i].toDouble(),
                          min: 0,
                          max: 180,
                          divisions: 12,
                          label: '${values[i]} min',
                          onChanged: (v) => setD(() => values[i] = v.toInt()),
                        ),
                      ),
                      SizedBox(width: 42, child: Text('${values[i]}', textAlign: TextAlign.right)),
                    ]),
                  const Divider(),
                  Text(
                    'Total : ${total ~/ 60}h${(total % 60).toString().padLeft(2, '0')} par semaine',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(c, values), child: const Text('Enregistrer')),
            ],
          );
        },
      ),
    );
    if (r != null) {
      setState(() => dailyCapacity = r);
      _persist();
    }
  }

  static const _boostWords = ['priorité', 'prioritaire', 'plus de', 'insister', 'focus', 'surtout', 'concentre'];
  static const _excludeWords = ['pas de', 'sans', 'aucun', 'évite', 'éviter', 'skip', 'stop', 'zero', 'zéro'];
  static const _reduceWords = ['moins de', 'moins'];
  static const _stopWords = {'au', 'aux', 'de', 'des', 'du', 'la', 'le', 'les', 'un', 'une', 'et', 'en', 'dans', 'pour', 'sur', 'ce', 'ces'};
  static const _accentedChars = 'àâäáãåèêëéìîïíòôöóõùûüúçñÀÂÄÁÃÅÈÊËÉÌÎÏÍÒÔÖÓÕÙÛÜÚÇÑ';
  static const _plainChars = 'aaaaaaeeeeiiiioooooouuuucnAAAAAAEEEEIIIIOOOOOOUUUUCN';

  /// Retire les accents et met en minuscules, pour que "priorite"/"interpretation" tapes
  /// sans accent correspondent quand meme a "priorité"/"Interprétation".
  String _fold(String s) {
    var out = s.toLowerCase();
    for (var i = 0; i < _accentedChars.length; i++) {
      out = out.replaceAll(_accentedChars[i], _plainChars[i].toLowerCase());
    }
    return out;
  }

  /// Vrai si [segment] (deja "folded") mentionne [name] : soit tel quel, soit via l'un de
  /// ses mots significatifs (4 lettres ou plus, hors articles/prepositions) sur une
  /// frontiere de mot — pour reconnaitre un nom raccourci ("sonate" pour "Sonate au clair
  /// de lune") independamment des accents.
  bool _mentions(String segment, String name) {
    final foldedSegment = _fold(segment);
    final lower = _fold(name);
    if (lower.isEmpty) return false;
    if (foldedSegment.contains(lower)) return true;
    bool isLetter(String ch) => RegExp(r'[a-z0-9]', caseSensitive: false).hasMatch(ch);
    bool wordBoundaryMatch(String word) {
      var start = foldedSegment.indexOf(word);
      while (start != -1) {
        final before = start == 0 ? '' : foldedSegment[start - 1];
        final afterIdx = start + word.length;
        final after = afterIdx >= foldedSegment.length ? '' : foldedSegment[afterIdx];
        if (!isLetter(before) && !isLetter(after)) return true;
        start = foldedSegment.indexOf(word, start + 1);
      }
      return false;
    }

    final words = lower.split(RegExp(r'\s+')).where((w) => w.length >= 4 && !_stopWords.contains(w));
    return words.any(wordBoundaryMatch);
  }

  /// Interprete un texte de consignes libres (ex: "priorité Sonate, moins de Skoove") et
  /// retourne un multiplicateur de poids par projet mentionne. Reconnait les noms de
  /// projets, les categories d'objectif et les methodes/applications, independamment des
  /// accents. Approche par mots-cles simple (pas un veritable LLM) : elle decoupe le texte
  /// en segments separes par virgule/point-virgule/"et", puis cherche dans chaque segment
  /// un mot d'intention (priorite/plus/moins/pas de) et une entite connue.
  String _methodPlanningDetails(Project project) {
    final base = project.goal.trim();
    final method = project.method == null ? null : methodDefinitions.where((m) => m.name.toLowerCase() == project.method!.toLowerCase()).firstOrNull;
    if (method == null) return base;
    final parts = <String>[];
    if (base.isNotEmpty) parts.add(base);
    if (method.exercises.isNotEmpty) parts.add('Méthode : ${method.exercises}');
    if (method.objectives.isNotEmpty) parts.add('Objectif méthode : ${method.objectives}');
    return parts.join(' — ');
  }

  Map<String, double> _parseWeeklyInstructions(String text) {
    final folded = _fold(text.trim());
    if (folded.isEmpty) return {};
    final multipliers = <String, double>{};
    final segments = folded.split(RegExp(r'[,;]|\bet\b'));

    for (final segment in segments) {
      double? mult;
      if (_excludeWords.any((w) => segment.contains(_fold(w)))) {
        mult = 0.0;
      } else if (_reduceWords.any((w) => segment.contains(_fold(w)))) {
        mult = 0.35;
      } else if (_boostWords.any((w) => segment.contains(_fold(w)))) {
        mult = 2.5;
      }
      if (mult == null) continue;

      for (final p in projects) {
        if (_mentions(segment, p.name)) {
          multipliers[p.id] = mult;
        }
      }
      for (final cat in objectiveCategories) {
        if (segment.contains(_fold(cat))) {
          // 'Lecture' et 'Improvisation' n'existent pas comme etape de morceau
          // (Project.weakestCategory) : on les fait pointer vers la categorie de
          // recommandation la plus proche, comme pour plannedMinutesByCategory.
          final effectiveCat = const {'Lecture': 'Répertoire', 'Improvisation': 'Technique'}[cat] ?? cat;
          for (final p in projects.where((p) => p.weakestCategory == effectiveCat)) {
            multipliers[p.id] = mult;
          }
        }
      }
      for (final m in learningMethods) {
        if (segment.contains(_fold(m))) {
          for (final p in projects.where((p) => p.method == m)) {
            multipliers[p.id] = mult;
          }
        }
      }
      if (segment.contains('revis')) {
        // Une consigne du type « priorité à réviser : A, B » doit cibler
        // uniquement A et B. Si aucun morceau n'est nommé dans le segment,
        // on conserve le comportement générique : tous les morceaux du
        // répertoire d'entretien sont concernés.
        final namedReview = projects.where((p) =>
            p.effectiveStatus == 'Répertoire d’entretien' && _mentions(segment, p.name)).toList();
        if (namedReview.isNotEmpty) {
          for (final p in namedReview) {
            multipliers[p.id] = mult;
          }
        } else {
          // Cas particulier : la suggestion automatique peut contenir
          // plusieurs noms séparés par des virgules. On analyse alors
          // l'ensemble de la consigne, pas seulement le segment courant.
          final isExplicitReviewPriority = folded.contains('priorite a reviser') ||
              folded.contains('priorite a reviser :');
          if (!isExplicitReviewPriority) {
            for (final p in projects.where((p) => p.effectiveStatus == 'Répertoire d’entretien')) {
              multipliers[p.id] = mult;
            }
          }
        }
      }
      if (segment.contains(_fold('en cours'))) {
        for (final p in projects.where((p) => p.effectiveStatus != 'Répertoire d’entretien')) {
          multipliers[p.id] = mult;
        }
      }
    }
    return multipliers;
  }

  /// Genere une proposition de planning pour les 7 prochains jours a partir de la
  /// repartition recommandee par projet, en remplacant les seances non terminees de la semaine.
  /// Propose d'abord un champ de consignes libres, interpretees via [_parseWeeklyInstructions].
  void _showInstructionsHelp(BuildContext parentContext, TextEditingController textController, StateSetter setDialogState) {
    Widget section(String title, List<String> items) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: items
                    .map((t) => ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(t, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            final current = textController.text.trim();
                            textController.text = current.isEmpty ? t : '$current $t';
                            textController.selection = TextSelection.collapsed(offset: textController.text.length);
                            setDialogState(() {});
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        );

    showDialog<void>(
      context: parentContext,
      builder: (c) => AlertDialog(
        title: const Text('Commandes (clique pour ajouter)'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clique sur un mot ci-dessous pour l\'ajouter à tes consignes, ou combine-les toi-même. Chaque phrase doit avoir un mot d\'intention et une entité reconnue. Les accents sont optionnels ("priorite" ou "priorité" fonctionnent tous les deux).',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                section('Prioriser (×2,5)', _boostWords),
                section('Réduire (×0,35)', _reduceWords),
                section('Exclure complètement', _excludeWords),
                section('Catégories reconnues', objectiveCategories),
                section('Méthodes reconnues', learningMethods),
                section('Statuts disponibles', projectStatuses),
                if (projects.isNotEmpty) section('Tes morceaux actuels', projects.map((p) => p.name).toList()),
                const SizedBox(height: 4),
                const Text('Exemples', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('• "priorité Sonate, moins de Skoove"', style: TextStyle(fontSize: 13)),
                const Text('• "focus technique et mémorisation"', style: TextStyle(fontSize: 13)),
                const Text('• "pas de Let It Be cette semaine"', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))],
      ),
    );
  }

  /// Efface les seances non terminees des 7 prochains jours (les seances deja marquees
  /// terminees sont conservees), avec confirmation.
  Future<void> clearWeeklyPlan() async {
    final now = DateTime.now();
    final weekStart = startOfWeek(now);
    final weekEnd = weekStart.add(const Duration(days: 7)); // lundi suivant (exclu)
    final count = plan.where((x) => !x.completed && !x.date.isBefore(weekStart) && x.date.isBefore(weekEnd)).length;

    if (count == 0) {
      await showDialog<void>(
        context: navKey.currentContext!,
        builder: (c) => AlertDialog(
          title: const Text('Rien à effacer'),
          content: const Text('Aucune séance non terminée n\'est planifiée d\'ici la fin de la semaine.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
        ),
      );
      return;
    }

    final s = count > 1 ? 's' : '';
    final ok = await showDialog<bool>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        title: const Text('Effacer le planning ?'),
        content: Text(
          '$count séance$s non terminée$s d\'ici dimanche seront supprimée$s. Les jours déjà passés cette semaine et les séances déjà marquées terminées sont conservés.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      // Effacement de toute la semaine courante : lundi -> dimanche.
      // Les séances déjà terminées restent conservées.
      plan.removeWhere((x) => !x.completed && !x.date.isBefore(weekStart) && x.date.isBefore(weekEnd));
    });
    await _persist();
  }

  // ---------------------------------------------------------------------------
  // Routine ("journée type")
  // ---------------------------------------------------------------------------

  static const _dayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  static bool _sameDays(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String daysLabel(List<int> days) {
    final sorted = [...days]..sort();
    if (sorted.length == 7) return 'Tous les jours';
    if (_sameDays(sorted, [1, 2, 3, 4, 5])) return 'Semaine';
    if (_sameDays(sorted, [6, 7])) return 'Week-end';
    if (sorted.isEmpty) return 'Aucun jour';
    return sorted.map((d) => _dayLabels[d - 1]).join(', ');
  }

  Future<void> addOrEditRoutineItem([RoutineItem? existing]) async {
    final r = await showDialog<RoutineItem>(
      context: navKey.currentContext!,
      builder: (_) => RoutineDialog(existing: existing),
    );
    if (r == null) return;
    setState(() {
      if (existing == null) {
        routine.add(r..order = routine.length);
      } else {
        routine[routine.indexWhere((x) => x.id == existing.id)] = r;
      }
    });
    _persist();
  }

  void deleteRoutineItem(RoutineItem item) {
    setState(() => routine.removeWhere((x) => x.id == item.id));
    _persist();
  }

  void moveRoutineItem(RoutineItem item, int delta) {
    final sorted = [...routine]..sort((a, b) => a.order.compareTo(b.order));
    final idx = sorted.indexWhere((x) => x.id == item.id);
    final newIdx = idx + delta;
    if (idx == -1 || newIdx < 0 || newIdx >= sorted.length) return;
    setState(() {
      final tmp = sorted[idx];
      sorted[idx] = sorted[newIdx];
      sorted[newIdx] = tmp;
      for (var i = 0; i < sorted.length; i++) {
        sorted[i].order = i;
      }
      routine = sorted;
    });
    _persist();
  }

  bool _dayIsIn(DateTime d, List<int> days) => days.contains(d.weekday);

  /// Genere le planning des 7 prochains jours a partir de la routine ("journee type"),
  /// dans l'ordre de priorite de la liste. Les entrees a duree fixe (ex: mini-revision
  /// protegee) sont servies en premier chaque jour ; le reste du temps disponible est
  /// reparti au prorata entre les entrees restantes prevues ce jour-la.
  Future<MethodDefinition?> showMethodDefinitionDialog(BuildContext context, {MethodDefinition? initial}) {
    final name = TextEditingController(text: initial?.name ?? '');
    final description = TextEditingController(text: initial?.description ?? '');
    final objectives = TextEditingController(text: initial?.objectives ?? '');
    final exercises = TextEditingController(text: initial?.exercises ?? '');
    final duration = TextEditingController(text: (initial?.durationMinutes ?? 20).toString());
    String level = initial?.level ?? 'Tous niveaux';
    return showDialog<MethodDefinition>(context: context, builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      title: Text(initial == null ? 'Nouvelle méthode' : 'Modifier la méthode'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom de la méthode*')),
        TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
        TextField(controller: objectives, maxLines: 3, decoration: const InputDecoration(labelText: 'Objectifs')),
        TextField(controller: exercises, maxLines: 4, decoration: const InputDecoration(labelText: 'Exercices / déroulé')),
        TextField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Durée recommandée (minutes)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: level, decoration: const InputDecoration(labelText: 'Niveau'), items: const [
          DropdownMenuItem(value: 'Tous niveaux', child: Text('Tous niveaux')), DropdownMenuItem(value: 'Débutant', child: Text('Débutant')), DropdownMenuItem(value: 'Intermédiaire', child: Text('Intermédiaire')), DropdownMenuItem(value: 'Avancé', child: Text('Avancé')), DropdownMenuItem(value: 'Débutant à intermédiaire', child: Text('Débutant à intermédiaire')), DropdownMenuItem(value: 'Intermédiaire à avancé', child: Text('Intermédiaire à avancé')),
        ], onChanged: (v) => setD(() => level = v ?? level)),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')), FilledButton(onPressed: () { final mins = (int.tryParse(duration.text.trim()) ?? 20).clamp(1, 180); Navigator.pop(c, MethodDefinition(name: name.text.trim(), description: description.text.trim(), objectives: objectives.text.trim(), exercises: exercises.text.trim(), durationMinutes: mins, level: level)); }, child: const Text('Enregistrer'))],
    )));
  }

  void openRoutineScreen() {
    Navigator.of(navKey.currentContext!).push(MaterialPageRoute(
      builder: (_) => RoutineScreen(
        items: routine,
        onAdd: () => addOrEditRoutineItem(),
        onEdit: addOrEditRoutineItem,
        onDelete: deleteRoutineItem,
        onMove: moveRoutineItem,
        onGenerate: proposeWeeklyPlan,
      ),
    ));
  }

  /// Genere le planning des 7 prochains jours en deux passes : d'abord ta routine
  /// ("journee type") reserve son temps chaque jour concerne (les entrees a duree fixe
  /// en priorite), puis le temps restant chaque jour est reparti entre tes morceaux actifs
  /// selon leur avancement/priorite. La routine est un complement au planning, pas un
  /// remplacement : les deux se combinent dans une seule generation.
  Future<void> proposeWeeklyPlan({bool skipInstructionsDialog = false}) async {
    final ctrl = TextEditingController(text: weeklyInstructions);
    final instructions = skipInstructionsDialog
        ? weeklyInstructions
        : await showDialog<String>(
      context: navKey.currentContext!,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Row(children: [
            const Expanded(child: Text('Proposer un planning')),
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Aide sur les consignes',
              onPressed: () => _showInstructionsHelp(c, ctrl, setD),
            ),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Les seances non terminees des 7 prochains jours seront remplacees. Ta routine reserve son temps en premier chaque jour concerne, puis le reste est reparti entre tes morceaux selon leur avancement et les consignes ci-dessous si tu en donnes.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Consignes pour cette semaine (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setD(() {}),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: ctrl.text.isEmpty
                        ? null
                        : () {
                            ctrl.clear();
                            setD(() {});
                            setState(() => weeklyInstructions = '');
                            _persist();
                          },
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Effacer les critères'),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showInstructionsHelp(c, ctrl, setD),
                  child: const Text(
                    'Ex : "priorité Sonate, moins de Skoove" — clique pour voir/ajouter des commandes',
                    style: TextStyle(color: Colors.grey, fontSize: 12, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Generer')),
          ],
        ),
      ),
    );
    if (instructions == null) return;
    setState(() => weeklyInstructions = instructions);
    _persist();

    final multipliers = _parseWeeklyInstructions(instructions);
    final rec = recommendedMinutesByProject(multipliers: multipliers.isEmpty ? null : multipliers);
    if (rec.isEmpty && routine.isEmpty) {
      await showDialog<void>(
        context: navKey.currentContext!,
        builder: (c) => AlertDialog(
          title: const Text('Rien à générer'),
          content: const Text('Ajoute au moins un morceau dont l\'avancement n\'est pas terminé, ou une entrée dans "Ma routine", pour générer une proposition.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Ok'))],
        ),
      );
      return;
    }

    final now = DateTime.now();
    final weekStart = startOfWeek(now); // toujours lundi
    final weekEnd = weekStart.add(const Duration(days: 7)); // lundi suivant (exclu)
    final days = List<DateTime>.generate(7, (i) => weekStart.add(Duration(days: i)));
    final sortedRoutine = [...routine]..sort((a, b) => a.order.compareTo(b.order));

    // Une nouvelle génération remplace les séances non terminées de l'ancien
    // planning, y compris celles qui sont en retard (ex. 31/8 -> 6/9).
    // On demande confirmation avant cette opération destructive. Les séances déjà
    // réalisées restent toujours conservées.
    final pendingCount = plan.where((x) => !x.completed).length;
    if (pendingCount > 0 && !skipInstructionsDialog) {
      final replace = await showDialog<bool>(
        context: navKey.currentContext!,
        builder: (c) => AlertDialog(
          title: const Text('Remplacer l’ancien planning ?'),
          content: Text(
            '$pendingCount séance${pendingCount > 1 ? 's' : ''} non terminée${pendingCount > 1 ? 's' : ''} vont être remplacée${pendingCount > 1 ? 's' : ''} par le nouveau planning des 7 prochains jours.\n\nLes séances déjà réalisées seront conservées dans l’historique.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remplacer')),
          ],
        ),
      );
      if (replace != true) return;
    }

    setState(() {
      // Repart proprement de zéro pour le planning à venir : toutes les séances
      // non terminées, quelle que soit leur date, sont supprimées. Les séances
      // déjà réalisées sont conservées pour l'historique et les statistiques.
      plan.removeWhere((x) => !x.completed);

      // Capacite restante par jour, entamee au fil des deux passes ci-dessous.
      final remainingByDay = {for (final d in days) d: dailyCapacity[d.weekday - 1]};

      // --- Passe 1 : la routine reserve son temps chaque jour concerne. ---
      if (sortedRoutine.isNotEmpty) {
        final slots = <DateTime, Map<String, double>>{for (final d in days) d: {}};
        var dayCursor = 0;
        for (final item in sortedRoutine) {
          if (item.cadence == 'jour') {
            for (final d in days) {
              if (_dayIsIn(d, item.days)) {
                slots[d]![item.id] = item.count.toDouble();
              }
            }
          } else {
            var remaining = item.count;
            var attempts = 0;
            while (remaining > 0 && attempts < days.length * 3) {
              final d = days[dayCursor % days.length];
              dayCursor++;
              attempts++;
              slots[d]!.update(item.id, (v) => v + 1, ifAbsent: () => 1);
              remaining--;
            }
          }
        }

        for (final d in days) {
          final daySlots = slots[d]!;
          if (daySlots.isEmpty) continue;
          var dayCapacity = remainingByDay[d]!.toDouble();
          final flexible = <String, double>{};

          for (final item in sortedRoutine) {
            if (!daySlots.containsKey(item.id)) continue;
            if (item.fixedMinutes != null && item.fixedMinutes! > 0) {
              final minutes = item.fixedMinutes! > dayCapacity ? dayCapacity.round() : item.fixedMinutes!;
              if (minutes <= 0) continue;
              plan.add(PlanItem(id: newId(), date: d, duration: minutes, title: item.label, details: ''));
              dayCapacity -= minutes;
            } else {
              flexible[item.id] = daySlots[item.id]!;
            }
          }

          final totalWeight = flexible.values.fold<double>(0, (a, b) => a + b);
          if (totalWeight > 0 && dayCapacity > 0) {
            flexible.forEach((itemId, weight) {
              final item = sortedRoutine.firstWhere((x) => x.id == itemId);
              var minutes = (dayCapacity * weight / totalWeight).round();
              if (item.maxMinutes != null && minutes > item.maxMinutes!) {
                minutes = item.maxMinutes!;
              }
              if (minutes <= 0) return;
              plan.add(PlanItem(id: newId(), date: d, duration: minutes, title: item.label, details: ''));
              dayCapacity -= minutes;
            });
          }

          remainingByDay[d] = dayCapacity.round();
        }
      }

      // --- Passe 2 : répartition quotidienne intelligente des morceaux. ---
      // V19 : on ne transforme plus la recommandation hebdomadaire en gros blocs
      // quotidiens. Chaque journée cherche un équilibre entre :
      //   • priorité et besoin réel du morceau ;
      //   • temps restant à lui consacrer dans la semaine ;
      //   • alternance avec les autres morceaux ;
      //   • durée minimale utile (15 min) et plafond quotidien (40 min).
      // L'objectif est d'obtenir des journées naturelles plutôt que 80/10/10.
      if (rec.isNotEmpty) {
        final remainingByProject = <String, int>{
          for (final e in rec.entries.where((e) => e.value > 0)) e.key: e.value,
        };
        final itemByDayAndProject = <String, PlanItem>{};
        final lastProjectByDay = <DateTime, String>{};
        const minUsefulMinutes = 15;
        const maxDailyMinutes = 40;

        double projectNeed(String projectId) {
          final p = projectById(projectId);
          if (p == null) return 0;
          // Même logique générale que la recommandation, mais volontairement
          // moins agressive : elle sert à choisir le prochain morceau du jour.
          final last = sessions
              .where((s) => s.projectId == projectId)
              .map((s) => s.date)
              .fold<DateTime?>(null, (latest, d) => latest == null || d.isAfter(latest) ? d : latest);
          final daysSince = last == null ? 999 : DateTime.now().difference(last).inDays;
          final recency = daysSince >= 14 ? 1.25 : (daysSince >= 7 ? 1.12 : 1.0);
          final stage = 1.0 + (1.0 - p.weakestStageValue) * .20;
          final priority = p.priority ? 1.30 : 1.0;
          return (1.0 + (1.0 - p.progress) * .80) * recency * stage * priority;
        }

        // On remplit chaque journée par petits blocs, en donnant d'abord à chaque
        // morceau présent une vraie durée de travail, puis en ajoutant du temps
        // aux morceaux qui en ont encore besoin. La rotation empêche le même
        // morceau de reprendre immédiatement la main.
        for (final day in days) {
          var guard = 0;
          while ((remainingByDay[day] ?? 0) >= minUsefulMinutes && remainingByProject.isNotEmpty && guard++ < 50) {
            final dayRemaining = remainingByDay[day]!;
            final candidates = remainingByProject.keys.where((id) => remainingByProject[id]! > 0).toList();
            if (candidates.isEmpty) break;

            // 1) Tant que plusieurs morceaux doivent encore être travaillés,
            //    favoriser ceux qui n'ont pas encore eu leur bloc aujourd'hui.
            final untouched = candidates.where((id) => !itemByDayAndProject.containsKey('${day.toIso8601String()}|$id')).toList();
            final pool = untouched.isNotEmpty && candidates.length > 1 ? untouched : candidates;

            // 2) Choix par score : besoin + poids hebdomadaire restant + bonus
            //    de rotation. Un morceau déjà travaillé aujourd'hui est pénalisé.
            String bestId = pool.first;
            var bestScore = -1.0;
            for (final id in pool) {
              final remaining = remainingByProject[id]!.toDouble();
              final weeklyShare = remaining / candidates.map((x) => remainingByProject[x]!.toDouble()).fold(0.0, (a, b) => a + b);
              final already = itemByDayAndProject['${day.toIso8601String()}|$id']?.duration ?? 0;
              final alternation = lastProjectByDay[day] == id ? 0.55 : 1.0;
              final need = projectNeed(id);
              final score = (weeklyShare * .75 + need * .25) * alternation * (already == 0 ? 1.15 : 1.0);
              if (score > bestScore) {
                bestScore = score;
                bestId = id;
              }
            }

            final key = '${day.toIso8601String()}|$bestId';
            final alreadyToday = itemByDayAndProject[key]?.duration ?? 0;
            final otherProjects = candidates.where((id) => id != bestId).toList();
            final cap = otherProjects.isNotEmpty ? maxDailyMinutes : dayRemaining;
            var room = cap - alreadyToday;
            if (room <= 0) {
              // Ce morceau a atteint son plafond pour aujourd'hui. On ne touche
              // surtout pas à son budget hebdomadaire : il sera repris un autre jour.
              final alternative = candidates.where((id) {
                final k = '${day.toIso8601String()}|$id';
                return (itemByDayAndProject[k]?.duration ?? 0) < maxDailyMinutes;
              }).toList();
              if (alternative.isEmpty) break;
              bestId = alternative.first;
              continue;
            }

            // Quand plusieurs morceaux sont disponibles, on privilégie un bloc
            // d'au moins 15 min. Le dernier bloc de la journée peut être plus court
            // uniquement s'il reste moins de 15 min disponibles.
            var chunk = [remainingByProject[bestId]!, dayRemaining, room].reduce((a, b) => a < b ? a : b);
            if (chunk >= minUsefulMinutes) {
              if (chunk > maxDailyMinutes) chunk = maxDailyMinutes;
              // Ne pas laisser un reliquat ridicule pour le même morceau :
              // lorsqu'il reste 30 min ou moins, on les prend en une seule fois.
              final projectRemainingAfter = remainingByProject[bestId]! - chunk;
              if (projectRemainingAfter > 0 && projectRemainingAfter < minUsefulMinutes && chunk < room) {
                final adjusted = chunk + projectRemainingAfter;
                if (adjusted <= room && adjusted <= maxDailyMinutes) chunk = adjusted;
              }
            }
            if (chunk <= 0) break;

            final project = projectById(bestId);
            if (project == null) {
              remainingByProject.remove(bestId);
              continue;
            }

            final existing = itemByDayAndProject[key];
            if (existing != null) {
              existing.duration += chunk;
            } else {
              final item = PlanItem(
                id: newId(),
                date: day,
                duration: chunk,
                title: project.name,
                details: _methodPlanningDetails(project),
                projectId: project.id,
                category: project.weakestCategory,
                method: project.method,
              );
              itemByDayAndProject[key] = item;
              plan.add(item);
            }

            remainingByProject[bestId] = remainingByProject[bestId]! - chunk;
            remainingByDay[day] = remainingByDay[day]! - chunk;
            lastProjectByDay[day] = bestId;
            if (remainingByProject[bestId]! <= 0) remainingByProject.remove(bestId);
          }
        }
      }
    });
    _persist();

    // La generation du planning peut intervenir apres le chargement initial.
    // On s'assure donc ici que les defis de la semaine existent bien, sans
    // jamais les regenerer s'ils sont deja presents.
    _ensureWeeklyChallenges();
    if (mounted) setState(() {});
  }

  Future<void> addOrEditSession([Session? existing, int? initialDuration]) async {
    final r = await showDialog<Session>(
      context: navKey.currentContext!,
      builder: (_) => SessionDialog(projects: projects, existing: existing, initialDuration: initialDuration),
    );
    if (r == null) return;
    setState(() {
      if (existing == null) {
        _capturePreviousProgress(r);
        sessions.insert(0, r);
      } else {
        // Une modification de session ne cree pas une nouvelle version
        // d'avancement : on conserve le snapshot d'origine.
        r.previousReading = existing.previousReading;
        r.previousHandsTogether = existing.previousHandsTogether;
        r.previousMemory = existing.previousMemory;
        r.previousInterpretation = existing.previousInterpretation;
        r.previousTempo = existing.previousTempo;
        r.newTempo = existing.newTempo;
        sessions[sessions.indexWhere((s) => s.id == existing.id)] = r;
      }
      _updateAutoProgress(existing?.projectId);
      _updateAutoProgress(r.projectId);
    });
    await _persist();

    // Une session AJOUTEE manuellement est une vraie fin de session, au même
    // titre qu'une session issue du chrono ou du planning : on propose donc
    // systématiquement la mise à jour des 4 étapes du morceau.
    // Une modification d'une session existante ne déclenche pas cette invite.
    if (existing == null && r.projectId != null) {
      await _offerDetailedProgress(r);
    }
    _checkCelebrations();
  }

  /// Recalcule l'avancement d'un projet a partir du temps total pratique, uniquement pour
  /// les projets ayant un objectif d'heures defini (targetHours). Appelee a chaque
  /// ajout/modification/suppression de session susceptible d'affecter ce total.
  void _updateAutoProgress(String? projectId) {
    if (projectId == null) return;
    final p = projectById(projectId);
    if (p == null || p.targetHours == null || p.targetHours! <= 0) return;
    final totalMinutes = sessions.where((s) => s.projectId == projectId).fold(0, (a, s) => a + s.duration);
    // IMPORTANT : l'avancement automatique ne modifie jamais les étapes détaillées.
    // reading / handsTogether / memory / interpretation restent toujours les données
    // saisies par l'utilisateur et sont donc récupérables si l'on repasse en manuel.
    p.progress = (totalMinutes / (p.targetHours! * 60)).clamp(0, 1);
  }

  /// Ouvre un chrono/minuteur pour la seance en cours. Si aucune entree n'est precisee,
  /// propose d'abord de choisir parmi les seances planifiees du jour (ou "Nouvelle session
  /// libre"). A l'arret, ouvre le formulaire de session pre-rempli avec la duree ecoulee ;
  /// si une seance planifiee etait ciblee, elle est marquee terminee avec cette duree, sinon
  /// une nouvelle entree est ajoutee au planning du jour pour que tout reste coherent.
  Future<void> startPracticeTimer([PlanItem? target]) async {
    PlanItem? chosen = target;
    if (chosen == null) {
      final now = DateTime.now();
      final todaysItems = plan
          .where((x) => !x.completed && x.date.year == now.year && x.date.month == now.month && x.date.day == now.day)
          .toList();
      if (todaysItems.isNotEmpty) {
        final result = await showDialog<Object>(
          context: navKey.currentContext!,
          builder: (c) => SimpleDialog(
            title: const Text('Chrono pour quelle séance ?'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'free'),
                child: const Row(children: [Icon(Icons.add, size: 18), SizedBox(width: 10), Text('Nouvelle session (libre)')]),
              ),
              const Divider(height: 1),
              ...todaysItems.map((x) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, x),
                    child: Text(x.title),
                  )),
            ],
          ),
        );
        if (result == null) return; // fenetre fermee sans choix
        if (result is PlanItem) chosen = result;
        // si result == 'free', chosen reste null intentionnellement
      }
    }

    final elapsedMinutes = await Navigator.of(navKey.currentContext!).push<int>(
      MaterialPageRoute(builder: (_) => const PracticeTimerScreen()),
    );
    if (elapsedMinutes == null) return;

    if (chosen != null) {
      final planItem = chosen;
      final r = await showDialog<Session>(
        context: navKey.currentContext!,
        builder: (_) => SessionDialog(
          projects: projects,
          initialDuration: elapsedMinutes,
          initialProjectId: planItem.projectId,
          initialType: planItem.category,
          initialNotes: planItem.details,
          initialMethod: planItem.method,
        ),
      );
      if (r == null) return;
      setState(() {
        _capturePreviousProgress(r);
        sessions.insert(0, r);
        planItem.completed = true;
        planItem.duration = r.duration;
        planItem.sourceSessionId = r.id;
        _updateAutoProgress(r.projectId);
      });
      _persist();
      await _offerDetailedProgress(r);
    } else {
      final r = await showDialog<Session>(
        context: navKey.currentContext!,
        builder: (_) => SessionDialog(projects: projects, initialDuration: elapsedMinutes),
      );
      if (r == null) return;
      setState(() {
        _capturePreviousProgress(r);
        sessions.insert(0, r);
        _updateAutoProgress(r.projectId);
        plan.add(PlanItem(
          id: newId(),
          date: DateTime.now(),
          duration: r.duration,
          title: projectById(r.projectId)?.name ?? 'Pratique libre',
          details: r.notes,
          projectId: r.projectId,
          category: r.type,
          method: r.method,
          completed: true,
          sourceSessionId: r.id,
        ));
      });
      _persist();
      await _offerDetailedProgress(r);
    }
    _checkCelebrations();
  }

  /// Ouvre rapidement les étapes détaillées du morceau après une session terminée.
  /// Disponible quel que soit le mode d'avancement (manuel ou automatique). Propose aussi
  /// de mettre à jour le tempo si ce morceau en suit un (tempo actuel ou cible déjà réglés),
  /// ce qui alimente la courbe de progression du tempo dans le temps.
  Future<void> _offerDetailedProgress(Session session) async {
    final projectId = session.projectId;
    if (projectId == null) return;
    final p = projectById(projectId);
    if (p == null) return;

    final result = await showDialog<_DetailedProgressResult>(
      context: navKey.currentContext!,
      builder: (_) => _DetailedProgressDialog(project: p),
    );
    if (result == null) return;
    setState(() {
      p.reading = result.reading;
      p.handsTogether = result.handsTogether;
      p.memory = result.memory;
      p.interpretation = result.interpretation;
      if (result.tempo > 0) p.currentTempo = result.tempo;
      session.newTempo = result.tempo > 0 ? result.tempo : null;
    });
    _persist();
  }

  /// Annule/supprime une session.
  /// Si cette session est la derniere session du morceau, on restaure l'etat
  /// detaille qui existait juste avant elle. Cela fonctionne aussi avec
  /// l'avancement automatique : les 4 etapes detaillees sont independantes.
  void _capturePreviousProgress(Session s) {
    final p = projectById(s.projectId);
    if (p == null) return;
    s.previousReading = p.reading;
    s.previousHandsTogether = p.handsTogether;
    s.previousMemory = p.memory;
    s.previousInterpretation = p.interpretation;
    s.previousTempo = p.currentTempo;
  }

  void deleteSession(Session s) {
    setState(() {
      // Le retour arrière ne s'applique que si la session supprimée est
      // réellement la dernière session conservée pour ce morceau.
      // On utilise l'ordre de la liste (la plus récente est en tête) plutôt
      // que la date saisie dans la session, qui peut avoir été modifiée.
      final projectSessions = s.projectId == null
          ? <Session>[]
          : sessions.where((other) => other.projectId == s.projectId).toList();
      final wasLatestForProject = projectSessions.isNotEmpty &&
          projectSessions.first.id == s.id;

      sessions.removeWhere((x) => x.id == s.id);

      // Une session provenant du planning doit redevenir non terminee.
      for (final x in plan) {
        if (x.sourceSessionId == s.id) {
          x.completed = false;
          x.sourceSessionId = null;
        }
      }

      final p = projectById(s.projectId);
      if (wasLatestForProject && p != null && s.hasProgressSnapshot) {
        p.reading = s.previousReading!;
        p.handsTogether = s.previousHandsTogether!;
        p.memory = s.previousMemory!;
        p.interpretation = s.previousInterpretation!;
        // p.progress est un champ stocké indépendant des 4 étapes ci-dessus
        // (voir ProjectDialog) : sans ce recalcul, il restait figé à l'ancienne
        // valeur (celle incluant la session qu'on vient de supprimer) pour tout
        // morceau en mode manuel — _updateAutoProgress() ne s'applique qu'aux
        // morceaux en mode "heures visées". Cela faussait ensuite le badge
        // "morceaux terminés", la fiche du morceau et les recommandations.
        if (p.targetHours == null || p.targetHours! <= 0) {
          p.progress = (p.reading + p.handsTogether + p.memory + p.interpretation) / 4;
        }
      }
      if (wasLatestForProject && p != null && s.previousTempo != null) {
        p.currentTempo = s.previousTempo!;
      }

      _updateAutoProgress(s.projectId);
      // Si le morceau repasse sous 100 % suite à cette suppression, on doit
      // pouvoir re-déclencher la célébration de fin de morceau plus tard.
      if (p != null && p.progress < 1) p.celebratedComplete = false;
    });
    _persist();
  }

  Future<void> addOrEditProject([Project? existing]) async {
    final totalMinutes = existing == null
        ? 0
        : sessions.where((s) => s.projectId == existing.id).fold(0, (a, s) => a + s.duration);
    final projectSessions = existing == null
        ? <Session>[]
        : (sessions.where((s) => s.projectId == existing.id).toList()..sort((a, b) => b.date.compareTo(a.date)));
    final r = await showDialog<Project>(
      context: navKey.currentContext!,
      builder: (_) => ProjectDialog(existing: existing, totalMinutesPracticed: totalMinutes, projectSessions: projectSessions),
    );
    if (r == null) return;
    setState(() {
      if (existing == null) {
        projects.add(r);
      } else {
        projects[projects.indexWhere((p) => p.id == existing.id)] = r;
      }
      // Une méthode utilisée par un projet doit toujours apparaître dans
      // la liste générale des méthodes, même si elle vient d'un ancien import.
      _syncMethodsFromUsage();
    });
    _persist();
    _checkCelebrations();
  }

  void deleteProject(Project p) {
    setState(() {
      projects.removeWhere((x) => x.id == p.id);
      for (final s in sessions) {
        if (s.projectId == p.id) s.projectId = null;
      }
      for (final x in plan) {
        if (x.projectId == p.id) x.projectId = null;
      }
    });
    _persist();
  }

  Future<void> addOrEditPlan([PlanItem? existing]) async {
    final r = await showDialog<PlanItem>(
      context: navKey.currentContext!,
      builder: (_) => PlanDialog(projects: projects, existing: existing),
    );
    if (r == null) return;
    setState(() {
      if (existing == null) {
        plan.add(r);
      } else {
        plan[plan.indexWhere((x) => x.id == existing.id)] = r;
      }
    });
    _persist();
  }

  void deletePlan(PlanItem x) {
    setState(() => plan.removeWhere((y) => y.id == x.id));
    _persist();
  }

  /// Decocher reste un simple bascule. Cocher (marquer termine) demande la duree
  /// pratiquee — par defaut celle prevue, modifiable a la main, ou via le chrono — et
  /// logue une session correspondante pour que les statistiques restent exactes.
  Future<void> togglePlanCompleted(PlanItem x) async {
    if (x.completed) {
      final source = x.sourceSessionId == null
          ? null
          : sessions.where((s) => s.id == x.sourceSessionId).firstOrNull;
      if (source != null) {
        deleteSession(source);
      } else {
        setState(() => x.completed = false);
        _persist();
      }
      return;
    }

    final durationCtrl = TextEditingController(text: x.duration.toString());
    final result = await showDialog<Object>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        title: Text('Terminé : ${x.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: durationCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Durée pratiquée (minutes)'),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(c, 'timer'),
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: const Text('Utiliser le chrono à la place'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(c, int.tryParse(durationCtrl.text) ?? x.duration),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == 'timer') {
      await startPracticeTimer(x);
      return;
    }
    final minutes = result as int;
    final newSession = Session(
      id: newId(),
      date: DateTime.now(),
      duration: minutes,
      projectId: x.projectId,
      type: x.category ?? 'Répertoire',
      rating: 4,
      notes: x.details,
      method: x.method,
    );
    setState(() {
      x.completed = true;
      x.duration = minutes;
      _capturePreviousProgress(newSession);
      sessions.insert(0, newSession);
      x.sourceSessionId = newSession.id;
      _updateAutoProgress(x.projectId);
    });
    _persist();
    await _offerDetailedProgress(newSession);
    _checkCelebrations();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final pages = [
      Home(
        projects: projects,
        sessions: sessions,
        plan: plan,
        minutes: minutes,
        weeklyTarget: weeklyTarget,
        streak: practiceStreak,
        suggestions: practiceSuggestions,
        challenges: thisWeekChallenges,
        challengeProgress: challengeProgress,
        badges: badges,
        onOpenBadges: openBadgesScreen,
        onOpenBilan: openBilanScreen,
        onStart: startPracticeTimer,
        onTogglePlan: togglePlanCompleted,
        onEditCapacity: editDailyCapacity,
        onQuickProject: () => addOrEditProject(),
        onQuickPlan: () => addOrEditPlan(),
        onExport: exportData,
        darkMode: darkMode,
        onToggleDarkMode: () {
          setState(() => darkMode = !darkMode);
          _persist();
        },
        onImport: importData,
        projectById: projectById,
        onOrientSuggestion: orientSuggestion,
        onOrientSuggestionThisWeek: orientSuggestionThisWeek,
      ),
      Sessions(
        items: sessions,
        onAdd: () => addOrEditSession(),
        onEdit: addOrEditSession,
        onDelete: deleteSession,
        projectById: projectById,
      ),
      Projects(items: projects, onAdd: () => addOrEditProject(), onEdit: addOrEditProject, onDelete: deleteProject),
      Week(
        items: plan,
        minutes: minutes,
        weeklyTarget: weeklyTarget,
        recommended: recommendedMinutesByCategory,
        planned: plannedMinutesByCategory,
        onAdd: () => addOrEditPlan(),
        onEdit: addOrEditPlan,
        onDelete: deletePlan,
        onToggle: togglePlanCompleted,
        onPropose: proposeWeeklyPlan,
        onClear: clearWeeklyPlan,
        onEditCapacity: editDailyCapacity,
        onOpenRoutine: openRoutineScreen,
        onStartTimer: startPracticeTimer,
        projectById: projectById,
      ),
      MethodsScreen(
        methods: methodDefinitions,
        onAdd: () async {
          final m = await showMethodDefinitionDialog(navKey.currentContext!);
          if (m == null || m.name.isEmpty || methodDefinitions.any((x) => x.name.toLowerCase() == m.name.toLowerCase())) return;
          setState(() { methodDefinitions.add(m); learningMethods = methodDefinitions.map((x) => x.name).toList(); });
          await _persist();
        },
        onEdit: (old) async {
          final m = await showMethodDefinitionDialog(navKey.currentContext!, initial: old);
          if (m == null || m.name.isEmpty || (m.name.toLowerCase() != old.name.toLowerCase() && methodDefinitions.any((x) => x.name.toLowerCase() == m.name.toLowerCase()))) return;
          setState(() {
            final i = methodDefinitions.indexOf(old);
            if (i >= 0) {
              methodDefinitions[i] = m;
              for (final p in projects) if (p.method == old.name) p.method = m.name;
              for (final ss in sessions) if (ss.method == old.name) ss.method = m.name;
              for (final x in plan) if (x.method == old.name) x.method = m.name;
              learningMethods = methodDefinitions.map((x) => x.name).toList();
            }
          });
          await _persist();
        },
        onDelete: (m) async {
          final ok = await showDialog<bool>(context: navKey.currentContext!, builder: (c) => AlertDialog(title: const Text('Supprimer la méthode ?'), content: Text('Supprimer « ${m.name} » ?'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer'))]));
          if (ok == true) { setState(() { methodDefinitions.remove(m); learningMethods = methodDefinitions.map((x) => x.name).toList(); }); await _persist(); }
        },
      ),
    ];
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Piano Practice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        visualDensity: VisualDensity.standard,
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.standard,
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        body: SafeArea(child: pages[tab]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Accueil'),
            NavigationDestination(icon: Icon(Icons.music_note_outlined), selectedIcon: Icon(Icons.music_note), label: 'Sessions'),
            NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Morceaux'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Planning'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Méthodes'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets partages
// ---------------------------------------------------------------------------

class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext c) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Theme.of(c).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Theme.of(c).colorScheme.outlineVariant.withOpacity(.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

// ---------------------------------------------------------------------------
// Chrono / minuteur de pratique
// ---------------------------------------------------------------------------

class PracticeTimerScreen extends StatefulWidget {
  const PracticeTimerScreen({super.key});
  @override
  State<PracticeTimerScreen> createState() => _PracticeTimerScreenState();
}

class _PracticeTimerScreenState extends State<PracticeTimerScreen> {
  bool isCountdown = false;
  int targetMinutes = 25;
  int elapsedSeconds = 0;
  bool running = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (running) {
      _timer?.cancel();
      setState(() => running = false);
    } else {
      setState(() => running = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          elapsedSeconds++;
          if (isCountdown && elapsedSeconds >= targetMinutes * 60) {
            _timer?.cancel();
            running = false;
          }
        });
      });
    }
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      running = false;
      elapsedSeconds = 0;
    });
  }

  String _fmt(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext c) {
    final remaining = isCountdown ? (targetMinutes * 60 - elapsedSeconds).clamp(0, targetMinutes * 60) : elapsedSeconds;
    final displaySeconds = isCountdown ? remaining : elapsedSeconds;
    final ratio = isCountdown && targetMinutes > 0 ? (elapsedSeconds / (targetMinutes * 60)).clamp(0.0, 1.0) : null;
    final finished = isCountdown && elapsedSeconds >= targetMinutes * 60;

    return Scaffold(
      appBar: AppBar(title: const Text('Chrono de pratique')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!running && elapsedSeconds == 0)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Chrono libre')),
                    ButtonSegment(value: true, label: Text('Minuteur (pomodoro)')),
                  ],
                  selected: {isCountdown},
                  onSelectionChanged: (v) => setState(() => isCountdown = v.first),
                ),
              if (!running && elapsedSeconds == 0 && isCountdown) ...[
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: targetMinutes <= 5 ? null : () => setState(() => targetMinutes -= 5),
                  ),
                  Text('$targetMinutes min', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => setState(() => targetMinutes += 5),
                  ),
                ]),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (ratio != null)
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: CircularProgressIndicator(value: ratio, strokeWidth: 10),
                      ),
                    Text(
                      _fmt(displaySeconds),
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (finished)
                const Text('Temps écoulé !', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: finished ? null : _toggle,
                    icon: Icon(running ? Icons.pause : Icons.play_arrow),
                    label: Text(running ? 'Pause' : 'Démarrer'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: elapsedSeconds == 0 ? null : _reset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réinitialiser'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: elapsedSeconds == 0
                    ? null
                    : () {
                        _timer?.cancel();
                        final minutes = (elapsedSeconds / 60).round();
                        Navigator.of(context).pop(minutes < 1 ? 1 : minutes);
                      },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Terminer la séance'),
              ),
              TextButton(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.of(context).pop();
                },
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget progress(double v) =>
    ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: v, minHeight: 7));

/// Tuile de statistique compacte (icone encadree + libelle + valeur), reprenant le
/// meme langage visuel que la zone Tempo de la fiche Morceau (icone dans un badge
/// colore, libelle discret au-dessus d'une valeur en gras). Reutilisee dans le
/// Planning et les ecrans de bilan/stats pour harmoniser leur presentation.
Widget _statTile(BuildContext c, {
  required IconData icon,
  required String label,
  required String value,
  String? sub,
  Color? accent,
  Widget? trailing,
}) {
  final scheme = Theme.of(c).colorScheme;
  final color = accent ?? scheme.primary;
  return Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: scheme.surfaceContainerHighest.withOpacity(.42),
      border: Border.all(color: scheme.outlineVariant.withOpacity(.45)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 38, height: 38, alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 19, color: color),
      ),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (sub != null) ...[
          const SizedBox(height: 1),
          Text(sub, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ])),
      if (trailing != null) trailing,
    ]),
  );
}

/// En-tete de section pour les ecrans de bilan/stats : icone encadree + titre,
/// meme principe que l'en-tete de la zone Tempo de la fiche Morceau.
Widget _sectionHeader(BuildContext c, IconData icon, String title, {String? subtitle, Color? accent}) {
  final scheme = Theme.of(c).colorScheme;
  final color = accent ?? scheme.primary;
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      width: 30, height: 30, alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 16, color: color),
    ),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
      ],
    ])),
  ]);
}

Widget emptyState(String message) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
      ),
    );

class Suggestion {
  Suggestion(this.icon, this.text, {this.color = Colors.blueGrey, this.instruction});
  final IconData icon;
  final String text;
  final Color color;
  final String? instruction;
}

class WeeklyBilan {
  WeeklyBilan({
    required this.weekStart,
    required this.totalMinutes,
    required this.pieces,
    required this.bestDay,
    required this.bestDayMinutes,
    required this.daysPracticed,
    required this.avgRating,
  });
  final DateTime weekStart; // lundi de la semaine couverte par ce bilan
  final int totalMinutes;
  final List<MapEntry<Project, int>> pieces; // triees par temps decroissant
  final DateTime? bestDay;
  final int bestDayMinutes;
  final int daysPracticed;
  final double? avgRating;
}

class AppBadge {
  AppBadge(this.id, this.emoji, this.title, this.description, this.earned);
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool earned;
}

class Challenge {
  Challenge({
    required this.id,
    required this.type, // 'days' | 'category' | 'project'
    required this.description,
    required this.target,
    required this.weekStart,
    this.refId,
    this.celebrated = false,
  });
  final String id;
  String type;
  String description;
  int target;
  DateTime weekStart;
  String? refId; // categorie (type='category') ou id de projet (type='project')
  bool celebrated; // evite de re-declencher la celebration a chaque rebuild

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'description': description,
        'target': target,
        'weekStart': weekStart.toIso8601String(),
        'refId': refId,
        'celebrated': celebrated,
      };

  factory Challenge.fromJson(Map<String, dynamic> j) => Challenge(
        id: j['id'] as String,
        type: j['type'] as String,
        description: j['description'] as String,
        target: j['target'] as int,
        weekStart: DateTime.parse(j['weekStart'] as String),
        refId: j['refId'] as String?,
        celebrated: j['celebrated'] as bool? ?? false,
      );
}

Future<bool> confirmDelete(BuildContext c, String what) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: const Text('Supprimer ?'),
      content: Text('Veux-tu vraiment supprimer $what ? Cette action est irreversible.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  return r ?? false;
}

Widget swipeToDelete({required Key key, required Widget child, required String what, required VoidCallback onDelete}) {
  return Builder(
    builder: (c) => Dismissible(
      key: key,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => confirmDelete(c, what),
      onDismissed: (_) => onDelete(),
      child: child,
    ),
  );
}

List<DropdownMenuItem<Project?>> projectItems(List<Project> ps) => [
      const DropdownMenuItem(value: null, child: Text('Aucun')),
      ...ps.map((p) => DropdownMenuItem(value: p, child: Text(p.name))),
    ];

// ---------------------------------------------------------------------------
// Accueil
// ---------------------------------------------------------------------------

String _greeting(DateTime now, int streak) {
  if (streak >= 7) return '🔥 $streak jours d’affilée, tu assures !';
  if (streak >= 3) return '🔥 $streak jours d’affilée, tu assures !';
  if (streak == 2) return '👏 Deux jours de suite, continue comme ça !';
  if (streak == 1) return '🎹 Belle reprise, on continue !';
  if (now.hour < 12) return 'Bonjour 👋';
  if (now.hour < 18) return 'Bon après-midi 🎹';
  return 'Bonne soirée 🎵';
}

class Home extends StatelessWidget {
  const Home({
    super.key,
    required this.projects,
    required this.sessions,
    required this.plan,
    required this.minutes,
    required this.weeklyTarget,
    required this.streak,
    required this.suggestions,
    required this.onOpenBilan,
    required this.challenges,
    required this.challengeProgress,
    required this.badges,
    required this.onOpenBadges,
    required this.onStart,
    required this.onTogglePlan,
    required this.onEditCapacity,
    required this.onQuickProject,
    required this.onQuickPlan,
    required this.onExport,
    required this.darkMode,
    required this.onToggleDarkMode,
    required this.onImport,
    required this.projectById,
    required this.onOrientSuggestion,
    required this.onOrientSuggestionThisWeek,
  });
  final List<Project> projects;
  final List<Session> sessions;
  final List<PlanItem> plan;
  final int minutes;
  final int weeklyTarget;
  final int streak;
  final List<Suggestion> suggestions;
  final VoidCallback onOpenBilan;
  final List<Challenge> challenges;
  final int Function(Challenge) challengeProgress;
  final List<AppBadge> badges;
  final VoidCallback onOpenBadges;
  final void Function([PlanItem?]) onStart;
  final void Function(PlanItem) onTogglePlan;
  final VoidCallback onEditCapacity;
  final VoidCallback onQuickProject;
  final VoidCallback onQuickPlan;
  final VoidCallback onExport;
  final bool darkMode;
  final VoidCallback onToggleDarkMode;
  final VoidCallback onImport;
  final Project? Function(String?) projectById;
  final void Function(String) onOrientSuggestion;
  final Future<void> Function(String) onOrientSuggestionThisWeek;

  void _showBackupMenu(BuildContext c) {
    showDialog<void>(
      context: c,
      builder: (dc) => SimpleDialog(
        title: const Text('Réglages · V11'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dc);
              onToggleDarkMode();
            },
            child: Row(children: [
              Icon(darkMode ? Icons.dark_mode : Icons.light_mode),
              const SizedBox(width: 12),
              Expanded(child: Text(darkMode ? 'Mode sombre activé' : 'Mode sombre désactivé')),
              Switch(value: darkMode, onChanged: (_) {
                Navigator.pop(dc);
                onToggleDarkMode();
              }),
            ]),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dc);
              onExport();
            },
            child: const Row(children: [
              Icon(Icons.download_outlined),
              SizedBox(width: 12),
              Expanded(child: Text('Exporter mes données (.json)')),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dc);
              onImport();
            },
            child: const Row(children: [
              Icon(Icons.upload_outlined),
              SizedBox(width: 12),
              Expanded(child: Text('Restaurer une sauvegarde')),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final now = DateTime.now();
    final todayItems = plan
        .where((x) => x.date.year == now.year && x.date.month == now.month && x.date.day == now.day)
        .toList()..sort((a, b) => a.completed == b.completed ? a.id.compareTo(b.id) : (a.completed ? 1 : -1));
    final todayRemaining = todayItems.where((x) => !x.completed).fold(0, (a, x) => a + x.duration);
    final ratio = (minutes / weeklyTarget).clamp(0, 1).toDouble();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Expanded(
            child: Text(_greeting(now, streak), style: Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Sauvegarde des données',
            onPressed: () => _showBackupMenu(c),
          ),
        ]),
        const Text('Votre pratique du jour', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 10),
        CardBox(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(c).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.piano, color: Theme.of(c).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    todayItems.isEmpty ? 'Aucune séance prévue' : '${todayItems.length} séance${todayItems.length > 1 ? 's' : ''} aujourd’hui',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 3),
                  Text(todayItems.isEmpty ? 'Tu peux commencer une session libre.' : '$todayRemaining min à faire · ${todayItems.where((x) => x.completed).fold(0, (a, x) => a + x.duration)} min réalisés', style: const TextStyle(color: Colors.grey)),
                ]),
              ),
              if (todayItems.any((x) => !x.completed))
                IconButton.filled(
                  tooltip: 'Commencer la prochaine séance',
                  onPressed: () => onStart(todayItems.firstWhere((x) => !x.completed)),
                  icon: const Icon(Icons.play_arrow),
                ),
            ],
          ),
        ),
        if (todayItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Builder(builder: (c) {
            final todayTarget = todayItems.fold(0, (a, x) => a + x.duration);
            final todayDone = todayItems.where((x) => x.completed).fold(0, (a, x) => a + x.duration);
            final todayRatio = todayTarget == 0 ? 0.0 : (todayDone / todayTarget).clamp(0.0, 1.0).toDouble();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              progress(todayRatio),
              const SizedBox(height: 4),
              Text('${(todayRatio * 100).round()} % de la journée · ${practiceBalanceLabel(practiced: todayDone, target: todayTarget)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]);
          }),
        ],
        // Répertoire d'entretien : visibilité immédiate des morceaux qui commencent
        // à être oubliés. Aucun nouveau champ n'est stocké : la date est calculée
        // directement depuis l'historique réel des sessions.
        Builder(builder: (c) {
          final review = projects
              .where((p) => p.effectiveStatus == 'Répertoire d’entretien')
              .toList()
            ..sort((a, b) => daysSinceLastProjectSession(b, sessions)
                .compareTo(daysSinceLastProjectSession(a, sessions)));
          if (review.isEmpty) return const SizedBox.shrink();
          final urgent = review.where((p) => daysSinceLastProjectSession(p, sessions) >= 7).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Répertoire d’entretien', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            CardBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.library_music_outlined, color: Theme.of(c).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    urgent.isEmpty ? 'Tout est à jour' : '${urgent.length} morceau${urgent.length > 1 ? 'x' : ''} à revoir',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  )),
                  if (urgent.isNotEmpty) Text('${urgent.length}', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.primary)),
                ]),
                const SizedBox(height: 10),
                ...review.take(3).map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Text(p.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(reviewDueLabel(p, sessions), style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                    ])),
                    TextButton(
                      onPressed: () => onStart(PlanItem(id: newId(), date: DateTime.now(), duration: 20, title: p.name, details: 'Révision · ${nextWorkRecommendation(p)}', projectId: p.id, category: 'Répertoire', method: p.method)),
                      child: const Text('20 min'),
                    ),
                  ]),
                )),
              ]),
            ),
            const SizedBox(height: 16),
          ]);
        }),
        const Text('Semaine en cours', style: TextStyle(color: Colors.grey)),
        if (streak > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.deepOrange.withOpacity(.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔥', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  streak == 1 ? '1 jour d\'affilée' : '$streak jours d\'affilée',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        CardBox(
          child: InkWell(
            onTap: onEditCapacity,
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 84,
                        height: 84,
                        child: CircularProgressIndicator(
                          value: ratio,
                          strokeWidth: 8,
                          backgroundColor: Theme.of(c).colorScheme.primary.withOpacity(.12),
                        ),
                      ),
                      Text('${(ratio * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pratique cette semaine', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')} sur ${weeklyTarget ~/ 60}h${(weeklyTarget % 60).toString().padLeft(2, '0')} visées'),
                      const SizedBox(height: 4),
                      Row(children: const [
                        Icon(Icons.edit_outlined, size: 14, color: Colors.grey),
                        SizedBox(width: 4),
                        Text('Toucher pour régler tes disponibilités', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        CardBox(
          child: InkWell(
            onTap: onOpenBilan,
            child: Row(
              children: [
                Expanded(child: _sectionHeader(c, Icons.insights, 'Voir mon bilan de la semaine')),
                Icon(Icons.chevron_right, color: Theme.of(c).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        // La carte est toujours visible. Les défis de la semaine sont générés
        // une seule fois pour la semaine courante dans _ensureWeeklyChallenges().
        const SizedBox(height: 16),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(c, Icons.flag_outlined, 'Défis de la semaine'),
                const SizedBox(height: 12),
                for (final ch in challenges)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Builder(builder: (_) {
                      final current = challengeProgress(ch);
                      final done = current >= ch.target;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(done ? Icons.check_circle : Icons.flag_outlined, size: 18, color: done ? Colors.green : Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ch.description,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  decoration: done ? TextDecoration.lineThrough : null,
                                  color: done ? Colors.grey : null,
                                ),
                              ),
                            ),
                            Text('${current.clamp(0, ch.target)} / ${ch.target}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ]),
                          const SizedBox(height: 6),
                          progress((current / ch.target).clamp(0, 1).toDouble()),
                        ],
                      );
                    }),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        CardBox(
          child: InkWell(
            onTap: onOpenBadges,
            child: Row(
              children: [
                Expanded(child: _sectionHeader(c, Icons.emoji_events_outlined,
                  'Mes badges (${badges.where((b) => b.earned).length}/${badges.length})',
                  accent: Colors.amber.shade700)),
                Icon(Icons.chevron_right, color: Theme.of(c).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(onPressed: onStart, icon: const Icon(Icons.play_arrow), label: const Text('Session')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(onPressed: onQuickPlan, icon: const Icon(Icons.event_available), label: const Text('Planifier')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(onPressed: onQuickProject, icon: const Icon(Icons.add_circle_outline), label: const Text('Morceau')),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (suggestions.isNotEmpty) ...[
          const Text('💡 Suggestions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in suggestions.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(s.icon, size: 18, color: s.color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.text, style: const TextStyle(fontSize: 13)),
                              if (s.instruction != null)
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 0,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () {
                                        final next = s.instruction!;
                                        onOrientSuggestion(next);
                                        ScaffoldMessenger.of(c).showSnackBar(
                                          SnackBar(content: Text('Ajouté aux consignes pour la prochaine génération : « $next »')),
                                        );
                                      },
                                      icon: const Icon(Icons.event_repeat, size: 16),
                                      label: const Text('Semaine prochaine'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        final next = s.instruction!;
                                        await onOrientSuggestionThisWeek(next);
                                      },
                                      icon: const Icon(Icons.today, size: 16),
                                      label: const Text('Semaine en cours'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        const Text('À faire aujourd\'hui', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        CardBox(
          child: todayItems.isEmpty
              ? const Text("Aucune activité prévue aujourd'hui.")
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: _sectionHeader(c, Icons.today_outlined, 'Programme du jour')),
                      Text('$todayRemaining min restantes', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 10),
                    ...todayItems.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (item.completed ? Colors.green : categoryColor(item.category)).withOpacity(.12),
                              ),
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => onTogglePlan(item),
                                icon: Icon(item.completed ? Icons.check_circle : Icons.circle_outlined),
                                iconSize: item.completed ? 26 : 22,
                                color: item.completed ? Colors.green.shade600 : categoryColor(item.category),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (item.category != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        color: (item.completed ? Colors.grey : categoryColor(item.category)).withOpacity(.14),
                                      ),
                                      child: Text(item.category!, style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: item.completed ? Colors.grey : categoryColor(item.category),
                                        decoration: item.completed ? TextDecoration.lineThrough : null,
                                      )),
                                    ),
                                  ),
                                Text(item.title, style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: item.completed ? Colors.grey : null,
                                  decoration: item.completed ? TextDecoration.lineThrough : null,
                                )),
                                if (item.details.isNotEmpty) Text(item.details, style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  decoration: item.completed ? TextDecoration.lineThrough : null,
                                )),
                                if (item.duration > 0) Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Chip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: Icon(Icons.timer_outlined, size: 13, color: item.completed ? Colors.grey : null),
                                    label: Text('${item.duration} min', style: TextStyle(
                                      fontSize: 11,
                                      color: item.completed ? Colors.grey : null,
                                      decoration: item.completed ? TextDecoration.lineThrough : null,
                                    )),
                                  ),
                                ),
                              ]),
                            )),
                            if (!item.completed)
                              IconButton(
                                tooltip: 'Démarrer cette séance',
                                onPressed: () => onStart(item),
                                icon: const Icon(Icons.play_circle_outline),
                              ),
                          ]),
                        )),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('COMMENCER LA SÉANCE'),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        if (projects.isNotEmpty) ...[
          const Text('Mes morceaux', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...([...projects]..sort((a, b) => (b.priority ? 1 : 0) - (a.priority ? 1 : 0))).map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CardBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(p.emoji, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 8),
                        if (p.priority) ...[
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 6),
                        ],
                        Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Text('${(p.progress * 100).round()} %'),
                      ]),
                      const SizedBox(height: 8),
                      progress(p.progress),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.lightbulb_outline, size: 15, color: Theme.of(c).colorScheme.primary),
                        const SizedBox(width: 5),
                        Expanded(child: Text('À travailler : ${nextWorkRecommendation(p)}', style: TextStyle(fontSize: 11.5, color: Theme.of(c).colorScheme.onSurfaceVariant))),
                      ]),
                    ],
                  ),
                ),
              )),
        ],
        if (sessions.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Dernière session', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sessions.first.date.day}/${sessions.first.date.month} · ${sessions.first.duration} min',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(projectById(sessions.first.projectId)?.name ?? 'Pratique libre'),
                Text(sessions.first.notes, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

class Sessions extends StatefulWidget {
  const Sessions({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.projectById,
  });
  final List<Session> items;
  final VoidCallback onAdd;
  final void Function(Session) onEdit;
  final void Function(Session) onDelete;
  final Project? Function(String?) projectById;

  @override
  State<Sessions> createState() => _SessionsState();
}

class _SessionsState extends State<Sessions> {
  String search = '';
  String? typeFilter;
  String? methodFilter;
  int periodDays = 0;
  String sort = 'recent';

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  List<Session> get filtered {
    final now = DateTime.now();
    final from = periodDays == 0 ? null : _day(now).subtract(Duration(days: periodDays - 1));
    final q = search.trim().toLowerCase();
    final list = widget.items.where((s) {
      if (from != null && _day(s.date).isBefore(from)) return false;
      if (typeFilter != null && s.type != typeFilter) return false;
      if (methodFilter != null && s.method != methodFilter) return false;
      if (q.isNotEmpty) {
        final project = widget.projectById(s.projectId)?.name ?? 'Pratique libre';
        final text = '${project} ${s.type} ${s.method ?? ''} ${s.notes}'.toLowerCase();
        if (!text.contains(q)) return false;
      }
      return true;
    }).toList();
    list.sort((a, b) {
      switch (sort) {
        case 'long': return b.duration.compareTo(a.duration);
        case 'short': return a.duration.compareTo(b.duration);
        case 'piece':
          final an = widget.projectById(a.projectId)?.name ?? 'Pratique libre';
          final bn = widget.projectById(b.projectId)?.name ?? 'Pratique libre';
          return an.toLowerCase().compareTo(bn.toLowerCase());
        default: return b.date.compareTo(a.date);
      }
    });
    return list;
  }

  Map<DateTime, int> _minutesByDay(List<Session> list) {
    final out = <DateTime, int>{};
    for (final s in list) {
      final d = _day(s.date);
      out[d] = (out[d] ?? 0) + s.duration;
    }
    return out;
  }

  int _currentStreak(Map<DateTime, int> byDay) {
    var d = _day(DateTime.now());
    if ((byDay[d] ?? 0) == 0) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while ((byDay[d] ?? 0) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int _bestStreak(Map<DateTime, int> byDay) {
    if (byDay.isEmpty) return 0;
    final days = byDay.keys.where((d) => (byDay[d] ?? 0) > 0).toList()..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in days) {
      if (prev != null && d.difference(prev!).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  String _mins(int m) => m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
  String _wd(int weekday) => const ['L', 'M', 'M', 'J', 'V', 'S', 'D'][weekday - 1];

  Widget _weeklyChart(BuildContext c, Map<DateTime, int> byDay) {
    final today = _day(DateTime.now());
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final maxValue = days.map((d) => byDay[d] ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
    final total = days.fold<int>(0, (a, d) => a + (byDay[d] ?? 0));
    return CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _sectionHeader(c, Icons.bar_chart_outlined, 'Temps de pratique — 7 derniers jours')),
        Text('Total : ${_mins(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 14),
      SizedBox(height: 150, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: days.map((d) {
        final value = byDay[d] ?? 0;
        final h = maxValue == 0 ? 2.0 : (110 * value / maxValue).clamp(2.0, 110.0);
        return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('$value', style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 3),
          Container(height: h, decoration: BoxDecoration(color: Theme.of(c).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(5))),
          const SizedBox(height: 5),
          Text(_wd(d.weekday), style: const TextStyle(fontSize: 11)),
        ])));
      }).toList())),
    ]));
  }

  Widget _journal(BuildContext c, Map<DateTime, int> byDay) {
    final today = _day(DateTime.now());
    final start = today.subtract(const Duration(days: 83));
    final maxValue = byDay.values.fold<int>(0, (a, b) => a > b ? a : b);
    final total = List.generate(84, (i) => byDay[_day(start.add(Duration(days: i)))] ?? 0).fold<int>(0, (a, b) => a + b);
    return CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _sectionHeader(c, Icons.calendar_view_month_outlined, 'Journal de bord & régularité')),
        Text('Total : ${_mins(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('🔥', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text('Série actuelle : ${_currentStreak(byDay)} j', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.deepOrange, fontSize: 12)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Theme.of(c).colorScheme.primary.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events_outlined, size: 14, color: Theme.of(c).colorScheme.primary),
            const SizedBox(width: 5),
            Text('Meilleure série : ${_bestStreak(byDay)} j', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.primary, fontSize: 12)),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 3, runSpacing: 3, children: List.generate(84, (i) {
        final d = _day(start.add(Duration(days: i)));
        final m = byDay[d] ?? 0;
        final level = maxValue == 0 ? 0 : (m / maxValue * 4).ceil().clamp(1, 4);
        return Tooltip(message: '${d.day}/${d.month}/${d.year} · $m min', child: InkWell(onTap: () => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('${d.day}/${d.month}/${d.year} : ${_mins(m)}'))), child: Container(width: 15, height: 15, decoration: BoxDecoration(color: m == 0 ? Theme.of(c).colorScheme.surfaceContainerHighest : Theme.of(c).colorScheme.primary.withAlpha(35 + level * 45), borderRadius: BorderRadius.circular(3)))));
      })),
    ]));
  }

  @override
  Widget build(BuildContext c) {
    final list = filtered;
    final byDay = _minutesByDay(list);
    final methods = widget.items.map((s) => s.method).whereType<String>().where((s) => s.isNotEmpty).toSet().toList()..sort();
    return Column(children: [
      AppBar(title: const Text('Sessions'), actions: [IconButton(onPressed: widget.onAdd, icon: const Icon(Icons.add))]),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        _weeklyChart(c, byDay),
        const SizedBox(height: 12),
        _journal(c, byDay),
        const SizedBox(height: 12),
        CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: _sectionHeader(c, Icons.filter_alt_outlined, 'Filtrer / trier')), if (search.isNotEmpty || typeFilter != null || methodFilter != null || periodDays != 0) TextButton(onPressed: () => setState(() { search=''; typeFilter=null; methodFilter=null; periodDays=0; }), child: const Text('Réinitialiser'))]),
          const SizedBox(height: 10),
          TextField(decoration: const InputDecoration(labelText: 'Rechercher morceau, catégorie, méthode...', prefixIcon: Icon(Icons.search), isDense: true), onChanged: (v) => setState(() => search = v)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            DropdownButton<String?>(value: typeFilter, hint: const Text('Type'), items: [const DropdownMenuItem<String?>(value: null, child: Text('Tous les types')), ...objectiveCategories.map((v) => DropdownMenuItem<String?>(value:v, child:Text(v)))], onChanged: (v) => setState(() => typeFilter=v)),
            DropdownButton<String?>(value: methodFilter, hint: const Text('Méthode'), items: [const DropdownMenuItem<String?>(value: null, child: Text('Toutes les méthodes')), ...methods.map((v) => DropdownMenuItem<String?>(value:v, child:Text(v)))], onChanged: (v) => setState(() => methodFilter=v)),
            DropdownButton<int>(value: periodDays, items: const [DropdownMenuItem(value:0,child:Text('Toute la période')),DropdownMenuItem(value:7,child:Text('7 derniers jours')),DropdownMenuItem(value:30,child:Text('30 derniers jours'))], onChanged:(v)=>setState(()=>periodDays=v??0)),
            DropdownButton<String>(value: sort, items: const [DropdownMenuItem(value:'recent',child:Text('Plus récentes')),DropdownMenuItem(value:'long',child:Text('Durée longue')),DropdownMenuItem(value:'short',child:Text('Durée courte')),DropdownMenuItem(value:'piece',child:Text('Par morceau'))], onChanged:(v)=>setState(()=>sort=v??'recent')),
          ]),
          const SizedBox(height: 8),
          Text('${list.length} session${list.length > 1 ? 's' : ''} · ${_mins(list.fold<int>(0,(a,s)=>a+s.duration))}', style: const TextStyle(color: Colors.grey)),
        ])),
        const SizedBox(height: 12),
        if (list.isEmpty) emptyState('Aucune session ne correspond aux critères.')
        else ...list.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: swipeToDelete(
                key: ValueKey(s.id),
                what: 'cette session',
                onDelete: () => widget.onDelete(s),
                child: CardBox(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => widget.onEdit(s),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40, height: 40, alignment: Alignment.center,
                          decoration: BoxDecoration(color: categoryColor(s.type).withOpacity(.15), borderRadius: BorderRadius.circular(13)),
                          child: Icon(categoryIcon(s.type), size: 19, color: categoryColor(s.type)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(widget.projectById(s.projectId)?.name ?? 'Pratique libre', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                                if (s.rating > 0) Text('★' * s.rating, style: const TextStyle(color: Colors.amber, fontSize: 13)),
                              ]),
                              const SizedBox(height: 2),
                              Text('${s.date.day}/${s.date.month}', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 12)),
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: const Icon(Icons.timer_outlined, size: 13),
                                  label: Text('${s.duration} min', style: const TextStyle(fontSize: 11)),
                                ),
                                Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(categoryIcon(s.type), size: 13, color: categoryColor(s.type)),
                                  label: Text(s.type, style: const TextStyle(fontSize: 11)),
                                ),
                                if (s.method != null)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: const Icon(Icons.smartphone, size: 13),
                                    label: Text(s.method!, style: const TextStyle(fontSize: 11)),
                                  ),
                              ]),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Supprimer',
                          onPressed: () async {
                            if (await confirmDelete(c, 'cette session')) widget.onDelete(s);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )),
      ])),
    ]);
  }
}

class SessionDialog extends StatefulWidget {
  const SessionDialog({
    super.key,
    required this.projects,
    this.existing,
    this.initialDuration,
    this.initialProjectId,
    this.initialType,
    this.initialNotes,
    this.initialMethod,
  });
  final List<Project> projects;
  final Session? existing;
  final int? initialDuration;
  final String? initialProjectId;
  final String? initialType;
  final String? initialNotes;
  final String? initialMethod;
  @override
  State<SessionDialog> createState() => _SessionDialogState();
}

class _SessionDialogState extends State<SessionDialog> {
  Project? project;
  late String type;
  late int duration;
  late int rating;
  String? method;
  late TextEditingController durationCtrl;
  late TextEditingController notesCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    project = e == null
        ? widget.projects.where((p) => p.id == widget.initialProjectId).firstOrNull
        : widget.projects.where((p) => p.id == e.projectId).firstOrNull;
    type = e?.type ?? widget.initialType ?? 'Répertoire';
    duration = e?.duration ?? widget.initialDuration ?? 30;
    rating = e?.rating ?? 4;
    method = e?.method ?? widget.initialMethod;
    durationCtrl = TextEditingController(text: duration.toString());
    notesCtrl = TextEditingController(text: e?.notes ?? widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    durationCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier la session' : 'Nouvelle session'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Project?>(
              value: project,
              decoration: const InputDecoration(labelText: 'Morceau'),
              items: projectItems(widget.projects),
              onChanged: (v) => setState(() => project = v),
            ),
            TextField(
              controller: durationCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Durée (minutes)'),
              onChanged: (v) => setState(() => duration = int.tryParse(v) ?? duration),
            ),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'Type de travail'),
              items: objectiveCategories
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => type = v ?? type),
            ),
            DropdownButtonFormField<String?>(
              value: method,
              decoration: const InputDecoration(labelText: 'Application / méthode'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Aucune')),
                ...learningMethods.map((v) => DropdownMenuItem(value: v, child: Text(v))),
              ],
              onChanged: (v) => setState(() => method = v),
            ),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            DropdownButtonFormField<int>(
              value: rating,
              decoration: const InputDecoration(labelText: 'Note'),
              items: List.generate(5, (i) => DropdownMenuItem(value: i + 1, child: Text('★' * (i + 1)))),
              onChanged: (v) => setState(() => rating = v ?? rating),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(
            c,
            Session(
              id: widget.existing?.id ?? newId(),
              date: widget.existing?.date ?? DateTime.now(),
              duration: duration,
              projectId: project?.id,
              type: type,
              rating: rating,
              notes: notesCtrl.text,
              method: method,
            ),
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Projets
// ---------------------------------------------------------------------------

Widget _miniProgress(String label, double value) => Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label ${(value * 100).round()}%', style: const TextStyle(fontSize: 11)),
      avatar: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: value, strokeWidth: 2)),
    );

class Projects extends StatefulWidget {
  const Projects({super.key, required this.items, required this.onAdd, required this.onEdit, required this.onDelete});
  final List<Project> items;
  final VoidCallback onAdd;
  final void Function(Project) onEdit;
  final void Function(Project) onDelete;

  @override
  State<Projects> createState() => _ProjectsState();
}

class _ProjectsState extends State<Projects> {
  String? filterStatus;

  @override
  Widget build(BuildContext c) {
    final visible = filterStatus == null
        ? [...widget.items]
        : widget.items.where((p) => p.effectiveStatus == filterStatus).toList();
    final sorted = [...visible]..sort((a, b) {
      final statusCompare = projectStatuses.indexOf(a.effectiveStatus).compareTo(projectStatuses.indexOf(b.effectiveStatus));
      if (statusCompare != 0) return statusCompare;
      return (b.priority ? 1 : 0) - (a.priority ? 1 : 0);
    });
    return Column(
      children: [
        AppBar(title: const Text('Morceaux'), actions: [IconButton(onPressed: widget.onAdd, icon: const Icon(Icons.add))]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: DropdownButtonFormField<String?>(
            value: filterStatus,
            decoration: const InputDecoration(
              labelText: 'Filtrer par statut',
              prefixIcon: Icon(Icons.filter_list),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Tous les morceaux')),
              ...projectStatuses.map((status) => DropdownMenuItem<String?>(
                    value: status,
                    child: Text('${projectStatusEmoji(status)}  $status'),
                  )),
            ],
            onChanged: (v) => setState(() => filterStatus = v),
          ),
        ),
        Expanded(
          child: widget.items.isEmpty
              ? emptyState('Aucun morceau pour l\'instant.\nAppuie sur + pour en ajouter un.')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = sorted[i];
                    return swipeToDelete(
                      key: ValueKey(p.id),
                      what: 'ce morceau',
                      onDelete: () => widget.onDelete(p),
                      child: CardBox(
                        child: InkWell(
                          onTap: () => widget.onEdit(p),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(p.emoji, style: const TextStyle(fontSize: 28)),
                                const SizedBox(width: 8),
                                if (p.priority) ...[
                                  const Icon(Icons.star, color: Colors.amber, size: 20),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  tooltip: 'Supprimer',
                                  onPressed: () async {
                                    if (await confirmDelete(c, 'ce morceau')) widget.onDelete(p);
                                  },
                                ),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Theme.of(c).colorScheme.primaryContainer,
                                  ),
                                  child: Text('${projectStatusEmoji(p.effectiveStatus)}  ${p.effectiveStatus}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.onPrimaryContainer)),
                                ),
                                const Spacer(),
                                Text('${(p.progress * 100).round()} %', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.primary)),
                              ]),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(value: p.progress, minHeight: 8),
                              ),
                              const SizedBox(height: 12),
                              if (p.goal.trim().isNotEmpty) ...[
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Icon(Icons.flag_outlined, size: 18, color: Theme.of(c).colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(p.goal, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.3))),
                                ]),
                                const SizedBox(height: 14),
                              ],
                              Text('Progression du morceau', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.onSurface)),
                              const SizedBox(height: 8),
                              _stepProgressTile(c, 'Lecture', Icons.menu_book_outlined, p.reading),
                              _stepProgressTile(c, 'Mains ensemble', Icons.pan_tool_alt_outlined, p.handsTogether),
                              _stepProgressTile(c, 'Mémorisation', Icons.psychology_outlined, p.memory),
                              _stepProgressTile(c, 'Interprétation', Icons.music_note_outlined, p.interpretation),
                              Padding(
                                padding: const EdgeInsets.only(top: 2, bottom: 2),
                                child: Row(children: [
                                  Icon(Icons.trending_up, size: 15, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text('À renforcer : ${_weakestStepLabel(p)}',
                                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                                ]),
                              ),
                              if (p.currentTempo > 0 || p.targetTempo > 0 || p.measures.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: Theme.of(c).colorScheme.surfaceContainerHighest.withOpacity(.55),
                                  ),
                                  child: Row(children: [
                                    Icon(Icons.speed_outlined, color: Theme.of(c).colorScheme.primary),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('Tempo', style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                                      const SizedBox(height: 2),
                                      Text(
                                        p.currentTempo > 0 && p.targetTempo > 0
                                            ? '${p.currentTempo} → ${p.targetTempo} BPM'
                                            : '${p.currentTempo > 0 ? p.currentTempo : p.targetTempo} BPM',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                      ),
                                      if (p.currentTempo > 0 && p.targetTempo > 0) ...[
                                        const SizedBox(height: 6),
                                        ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: (p.currentTempo / p.targetTempo).clamp(0.0, 1.0), minHeight: 5)),
                                        const SizedBox(height: 4),
                                        Text(
                                          p.currentTempo >= p.targetTempo
                                              ? '🎯 Objectif de tempo atteint'
                                              : '${p.targetTempo - p.currentTempo} BPM restants',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: p.currentTempo >= p.targetTempo ? FontWeight.w700 : FontWeight.normal,
                                            color: p.currentTempo >= p.targetTempo ? Colors.green.shade700 : Theme.of(c).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ])),
                                    if (p.measures.isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      Container(width: 1, height: 34, color: Theme.of(c).colorScheme.outlineVariant),
                                      const SizedBox(width: 12),
                                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text('Mesures', style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                                        Text(p.measures, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      ]),
                                    ],
                                  ]),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => widget.onEdit(p), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Ouvrir la fiche'))),
                              if (p.method != null || p.targetHours != null) ...[
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  if (p.targetHours != null)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      avatar: const Icon(Icons.timer_outlined, size: 14),
                                      label: Text('Auto · ${p.targetHours!.round()} h', style: const TextStyle(fontSize: 12)),
                                      backgroundColor: Colors.indigo.withOpacity(.12),
                                    ),
                                  if (p.method != null)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      avatar: const Icon(Icons.smartphone, size: 14),
                                      label: Text(p.method!, style: const TextStyle(fontSize: 12)),
                                    ),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Widget _progressSlider(String label, double value, ValueChanged<double> onChanged) {
  final parts = label.trim().split(RegExp(r'\s+'));
  final iconText = parts.isNotEmpty && parts.first.length <= 2 ? parts.first : '🎵';
  final title = parts.length > 1 ? parts.sublist(1).join(' ') : label;
  final pct = (value * 100).round();

  return Builder(builder: (c) {
    final scheme = Theme.of(c).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: scheme.surfaceContainerHighest.withOpacity(.42),
        border: Border.all(color: scheme.outlineVariant.withOpacity(.45)),
      ),
      child: Column(children: [
        Row(children: [
          Container(width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
            child: Text(iconText, style: const TextStyle(fontSize: 18))),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          Text('$pct %', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: scheme.primary)),
        ]),
        Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged, padding: const EdgeInsets.only(top: 4)),
      ]),
    );
  });
}

Widget _stepProgressTile(BuildContext c, String label, IconData icon, double value) {
  final scheme = Theme.of(c).colorScheme;
  final pct = (value * 100).round();
  return Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(children: [
      Container(width: 30, height: 30, alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.primaryContainer.withOpacity(.75), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 17, color: scheme.primary)),
      const SizedBox(width: 9),
      SizedBox(width: 112, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(value: value.clamp(0.0, 1.0), minHeight: 8))),
      const SizedBox(width: 9),
      SizedBox(width: 38, child: Text('$pct %', textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
    ]),
  );
}

/// Etape la plus faible parmi les 4 curseurs du morceau, avec les memes libelles
/// que ceux affiches dans la fiche (_stepProgressTile) — volontairement distinct
/// de Project.weakestCategory, qui utilise la taxonomie des categories de
/// planning/sessions (Répertoire, Technique...) et n'a pas les memes libelles.
String _weakestStepLabel(Project p) {
  final steps = <String, double>{
    'Lecture': p.reading,
    'Mains ensemble': p.handsTogether,
    'Mémorisation': p.memory,
    'Interprétation': p.interpretation,
  };
  var label = 'Lecture';
  var lowest = steps[label]!;
  for (final e in steps.entries) {
    if (e.value < lowest) {
      lowest = e.value;
      label = e.key;
    }
  }
  return label;
}

class _DetailedProgressResult {
  _DetailedProgressResult({
    required this.reading,
    required this.handsTogether,
    required this.memory,
    required this.interpretation,
    required this.tempo,
  });
  final double reading, handsTogether, memory, interpretation;
  final int tempo; // 0 = tempo non renseigne pour cette session
}

/// Fenetre proposee juste apres une session terminee : mise a jour des 4 etapes du
/// morceau et, optionnellement, du tempo atteint. Un vrai StatefulWidget (plutot qu'un
/// showDialog + StatefulBuilder avec TextEditingController géré a la main) pour que le
/// controller suive le cycle de vie normal de l'element (initState/dispose), et pour que
/// l'appelant applique setState seulement une fois la fenetre bien refermee (Navigator.pop
/// renvoie un resultat, comme SessionDialog/ProjectDialog) plutot que pendant sa fermeture.
class _DetailedProgressDialog extends StatefulWidget {
  const _DetailedProgressDialog({required this.project});
  final Project project;
  @override
  State<_DetailedProgressDialog> createState() => _DetailedProgressDialogState();
}

class _DetailedProgressDialogState extends State<_DetailedProgressDialog> {
  late double reading, handsTogether, memory, interpretation;
  late TextEditingController tempoCtrl;

  @override
  void initState() {
    super.initState();
    reading = widget.project.reading;
    handsTogether = widget.project.handsTogether;
    memory = widget.project.memory;
    interpretation = widget.project.interpretation;
    tempoCtrl = TextEditingController(text: widget.project.currentTempo == 0 ? '' : widget.project.currentTempo.toString());
  }

  @override
  void dispose() {
    tempoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    final avg = (reading + handsTogether + memory + interpretation) / 4;
    final currentTempo = widget.project.currentTempo;
    final targetTempo = widget.project.targetTempo;
    final tempoProgress = currentTempo > 0 && targetTempo > 0
        ? (currentTempo / targetTempo).clamp(0.0, 1.0)
        : 0.0;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      title: Row(children: [
        Text(widget.project.emoji, style: const TextStyle(fontSize: 27)),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.project.name, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
      ]),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bilan de la session', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: scheme.primary)),
            const SizedBox(height: 5),
            Text('Mets à jour ce qui a réellement progressé aujourd’hui. Ces données restent disponibles même avec l’avancement automatique.',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: scheme.primaryContainer.withOpacity(.45),
                border: Border.all(color: scheme.primary.withOpacity(.15)),
              ),
              child: Row(children: [
                SizedBox(width: 58, height: 58, child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: avg.clamp(0.0, 1.0), strokeWidth: 6, backgroundColor: scheme.surface.withOpacity(.7)),
                  Text('${(avg * 100).round()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: scheme.primary)),
                ])),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Progression des étapes', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('Ajuste uniquement les étapes qui ont changé.',
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            _progressSlider('📖 Lecture / mains séparées', reading, (v) => setState(() => reading = v)),
            _progressSlider('🤝 Mains ensemble', handsTogether, (v) => setState(() => handsTogether = v)),
            _progressSlider('🧠 Mémorisation', memory, (v) => setState(() => memory = v)),
            _progressSlider('🎭 Interprétation', interpretation, (v) => setState(() => interpretation = v)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: scheme.surfaceContainerHighest.withOpacity(.42),
                border: Border.all(color: scheme.outlineVariant.withOpacity(.45)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.speed_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Tempo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                  if (currentTempo > 0) Text(
                    targetTempo > 0 ? '$currentTempo → $targetTempo BPM' : '$currentTempo BPM',
                    style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
                ]),
                if (currentTempo > 0 && targetTempo > 0) ...[
                  const SizedBox(height: 9),
                  ClipRRect(borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: tempoProgress, minHeight: 7)),
                  const SizedBox(height: 4),
                  Text(
                    tempoProgress >= 1 ? '🎯 Objectif de tempo atteint' : '${targetTempo - currentTempo} BPM restants',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: tempoProgress >= 1 ? FontWeight.w700 : FontWeight.normal,
                      color: tempoProgress >= 1 ? Colors.green.shade700 : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: tempoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Tempo atteint aujourd’hui',
                    suffixText: 'BPM',
                    hintText: targetTempo > 0 ? 'Cible : $targetTempo BPM' : 'Laisser vide si non applicable',
                    prefixIcon: const Icon(Icons.music_note_outlined),
                  ),
                ),
              ]),
            ),
          ],
        )),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Plus tard')),
        FilledButton.icon(
          onPressed: () {
            final tempo = int.tryParse(tempoCtrl.text) ?? 0;
            Navigator.pop(c, _DetailedProgressResult(
              reading: reading, handsTogether: handsTogether, memory: memory,
              interpretation: interpretation, tempo: tempo,
            ));
          },
          icon: const Icon(Icons.check),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, this.existing, this.totalMinutesPracticed = 0, this.projectSessions = const []});
  final Project? existing;
  final int totalMinutesPracticed;
  final List<Session> projectSessions;
  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  late TextEditingController nameCtrl;
  late TextEditingController goalCtrl;
  String name = '';
  String? method;
  bool priority = false;
  String emoji = '🎵';
  double progress = 0;
  String status = 'En cours de déchiffrement';
  bool statusIsManual = false;
  double reading = 0, handsTogether = 0, memory = 0, interpretation = 0;
  int currentTempo = 0, targetTempo = 0;
  late TextEditingController measuresCtrl, currentTempoCtrl, targetTempoCtrl;
  bool autoProgress = false;
  double targetHours = 10;

  @override
  void initState() {
    super.initState();
    name = widget.existing?.name ?? '';
    nameCtrl = TextEditingController(text: name);
    goalCtrl = TextEditingController(text: widget.existing?.goal ?? '');
    method = widget.existing?.method;
    priority = widget.existing?.priority ?? false;
    emoji = widget.existing?.emoji ?? '🎵';
    progress = widget.existing?.progress ?? 0;
    status = _normalizeProjectStatus(widget.existing?.status);
    statusIsManual = widget.existing?.statusIsManual ?? false;
    reading = widget.existing?.reading ?? progress;
    handsTogether = widget.existing?.handsTogether ?? progress;
    memory = widget.existing?.memory ?? progress;
    interpretation = widget.existing?.interpretation ?? progress;
    currentTempo = widget.existing?.currentTempo ?? 0;
    targetTempo = widget.existing?.targetTempo ?? 0;
    measuresCtrl = TextEditingController(text: widget.existing?.measures ?? '');
    currentTempoCtrl = TextEditingController(text: currentTempo == 0 ? '' : currentTempo.toString());
    targetTempoCtrl = TextEditingController(text: targetTempo == 0 ? '' : targetTempo.toString());
    autoProgress = widget.existing?.targetHours != null;
    targetHours = widget.existing?.targetHours ?? 10;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    goalCtrl.dispose();
    measuresCtrl.dispose();
    currentTempoCtrl.dispose();
    targetTempoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier le morceau' : 'Nouveau morceau'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom'),
              onChanged: (v) => setState(() => name = v),
            ),
            TextField(controller: goalCtrl, decoration: const InputDecoration(labelText: 'Objectif final')),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: emoji,
              decoration: const InputDecoration(labelText: 'Icône du morceau'),
              items: const [
                DropdownMenuItem(value: '🎵', child: Text('🎵  Musique')),
                DropdownMenuItem(value: '🎹', child: Text('🎹  Piano')),
                DropdownMenuItem(value: '🌙', child: Text('🌙  Sonate / calme')),
                DropdownMenuItem(value: '💧', child: Text('💧  Douceur')),
                DropdownMenuItem(value: '🎩', child: Text('🎩  Élégant')),
                DropdownMenuItem(value: '⭐', child: Text('⭐  Priorité')),
                DropdownMenuItem(value: '❤️', child: Text('❤️  Coup de cœur')),
                DropdownMenuItem(value: '🚀', child: Text('🚀  Challenge')),
              ],
              onChanged: (v) => setState(() => emoji = v ?? '🎵'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Avancement automatique'),
              subtitle: const Text('Calculé depuis le temps de pratique loggé, plutôt que réglé à la main'),
              value: autoProgress,
              onChanged: (v) => setState(() => autoProgress = v),
            ),
            if (autoProgress) ...[
              Row(children: [
                const Text('Objectif :'),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: targetHours <= 1 ? null : () => setState(() => targetHours--),
                ),
                Text('${targetHours.round()} h', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => targetHours++),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '${(widget.totalMinutesPracticed / 60).toStringAsFixed(1)} h pratiquées sur $targetHours h visées → ${((widget.totalMinutesPracticed / 60 / targetHours).clamp(0, 1) * 100).round()} %',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'L’avancement global est calculé automatiquement à partir du temps pratiqué. Les étapes ci-dessous restent toutefois enregistrées et modifiables.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ] else ...[
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Text('Avancement global (moyenne des étapes)')),
                Text(
                  '${(((reading + handsTogether + memory + interpretation) / 4) * 100).round()} %',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ]),
              const SizedBox(height: 10),
            ],
            const Align(alignment: Alignment.centerLeft, child: Text('Étapes du morceau', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ces étapes sont conservées même lorsque l’avancement automatique est activé.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(c).colorScheme.surfaceContainerHighest.withOpacity(.55),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Les 4 étapes du morceau', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text('Mets à jour uniquement ce qui a progressé aujourd’hui.', style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(height: 8),
            _progressSlider('📖  Lecture / mains séparées', reading, (v) => setState(() => reading = v)),
            _progressSlider('🤝  Mains ensemble', handsTogether, (v) => setState(() => handsTogether = v)),
            _progressSlider('🧠  Mémorisation', memory, (v) => setState(() => memory = v)),
            _progressSlider('🎭  Interprétation', interpretation, (v) => setState(() => interpretation = v)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(c).colorScheme.outlineVariant),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.speed_outlined, size: 19, color: Theme.of(c).colorScheme.primary), const SizedBox(width: 8), const Text('Tempo et zone de travail', style: TextStyle(fontWeight: FontWeight.w800))]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: currentTempoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tempo actuel', suffixText: 'BPM'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: targetTempoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tempo cible', suffixText: 'BPM'))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: measuresCtrl, decoration: const InputDecoration(labelText: 'Mesures à travailler', hintText: 'ex. 25–48', prefixIcon: Icon(Icons.format_list_numbered))),
              ]),
            ),
            if (widget.existing != null && (currentTempo > 0 || targetTempo > 0)) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final entries = widget.projectSessions
                        .where((s) => s.newTempo != null)
                        .map((s) => MapEntry(s.date, s.newTempo!))
                        .toList()
                      ..sort((a, b) => a.key.compareTo(b.key));
                    Navigator.of(c, rootNavigator: true).push(MaterialPageRoute(
                      builder: (_) => TempoHistoryScreen(
                        projectName: widget.existing!.name,
                        targetTempo: targetTempo,
                        entries: entries,
                      ),
                    ));
                  },
                  icon: const Icon(Icons.show_chart, size: 18),
                  label: const Text('Voir la courbe de tempo'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Align(alignment: Alignment.centerLeft, child: Text('Statut du morceau', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: statusIsManual && projectStatuses.contains(status) ? status : '__AUTO__',
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.timeline),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '__AUTO__',
                  child: Text('✨  Automatique (selon les 4 étapes)'),
                ),
                ...projectStatuses.map((v) => DropdownMenuItem<String>(
                      value: v,
                      child: Text('${projectStatusEmoji(v)}  $v'),
                    )),
              ],
              onChanged: (v) => setState(() {
                if (v == '__AUTO__') {
                  statusIsManual = false;
                  status = statusFromStages(
                    reading: reading,
                    handsTogether: handsTogether,
                    memory: memory,
                    interpretation: interpretation,
                  );
                } else {
                  statusIsManual = true;
                  status = v ?? 'En cours de déchiffrement';
                }
              }),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                statusIsManual
                    ? 'Statut manuel : il ne changera pas automatiquement.'
                    : 'Statut automatique actuel : ${statusFromStages(reading: reading, handsTogether: handsTogether, memory: memory, interpretation: interpretation)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: method,
              decoration: const InputDecoration(labelText: 'Méthode / application'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Aucune')),
                ...learningMethods.map((v) => DropdownMenuItem(value: v, child: Text(v))),
              ],
              onChanged: (v) => setState(() => method = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Priorité'),
              subtitle: const Text('Recevra plus de temps dans les propositions de planning'),
              value: priority,
              onChanged: (v) => setState(() => priority = v),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 4),
              Text(
                'Sessions réalisées (${widget.projectSessions.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (widget.projectSessions.isEmpty)
                const Text('Aucune session enregistrée pour ce morceau pour l\'instant.', style: TextStyle(color: Colors.grey, fontSize: 13))
              else
                ...widget.projectSessions.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text('${s.date.day}/${s.date.month}/${s.date.year}', style: const TextStyle(fontSize: 12)),
                          ),
                          Expanded(
                            child: Text('${s.duration} min · ${s.type}${s.method != null ? ' · ${s.method}' : ''}', style: const TextStyle(fontSize: 12)),
                          ),
                          Text('★' * s.rating, style: const TextStyle(color: Colors.amber, fontSize: 11)),
                        ],
                      ),
                    )),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(
          onPressed: name.trim().isEmpty
              ? null
              : () {
                  final newProgress = autoProgress
                      ? (widget.totalMinutesPracticed / 60 / targetHours).clamp(0, 1).toDouble()
                      : (reading + handsTogether + memory + interpretation) / 4;
                  Navigator.pop(
                    c,
                    Project(
                      id: widget.existing?.id ?? newId(),
                      name: name,
                      emoji: emoji,
                      progress: newProgress,
                      goal: goalCtrl.text,
                      method: method,
                      priority: priority,
                      status: status,
                      statusIsManual: statusIsManual,
                      reading: reading,
                      handsTogether: handsTogether,
                      memory: memory,
                      interpretation: interpretation,
                      currentTempo: int.tryParse(currentTempoCtrl.text) ?? 0,
                      targetTempo: int.tryParse(targetTempoCtrl.text) ?? 0,
                      measures: measuresCtrl.text.trim(),
                      targetHours: autoProgress ? targetHours : null,
                      celebratedComplete: newProgress >= 1 ? (widget.existing?.celebratedComplete ?? false) : false,
                    ),
                  );
                },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Semaine / planning
// ---------------------------------------------------------------------------

class Week extends StatefulWidget {
  const Week({
    super.key,
    required this.items,
    required this.minutes,
    required this.weeklyTarget,
    required this.recommended,
    required this.planned,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onPropose,
    required this.onClear,
    required this.onEditCapacity,
    required this.onOpenRoutine,
    required this.onStartTimer,
    required this.projectById,
  });
  final List<PlanItem> items;
  final int minutes;
  final int weeklyTarget;
  final Map<String, int> recommended;
  final Map<String, int> planned;
  final VoidCallback onAdd;
  final void Function(PlanItem) onEdit;
  final void Function(PlanItem) onDelete;
  final void Function(PlanItem) onToggle;
  final VoidCallback onPropose;
  final VoidCallback onClear;
  final VoidCallback onEditCapacity;
  final VoidCallback onOpenRoutine;
  final void Function(PlanItem) onStartTimer;
  final Project? Function(String?) projectById;

  @override
  State<Week> createState() => _WeekState();
}

class _WeekState extends State<Week> {
  DateTime? filtreDate;
  String filtreMotCle = '';

  static String weekday(int n) => ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'][n - 1];

  @override
  Widget build(BuildContext c) {
    final filtered = widget.items.where((x) {
      if (filtreDate != null &&
          (x.date.year != filtreDate!.year || x.date.month != filtreDate!.month || x.date.day != filtreDate!.day)) {
        return false;
      }
      if (filtreMotCle.trim().isEmpty) return true;
      final q = filtreMotCle.toLowerCase().trim();
      return x.motsCles.any((t) => t.toLowerCase().contains(q)) ||
          x.title.toLowerCase().contains(q) ||
          x.details.toLowerCase().contains(q) ||
          (x.category?.toLowerCase().contains(q) ?? false) ||
          (x.method?.toLowerCase().contains(q) ?? false);
    }).toList();
    final sorted = [...filtered]..sort((a, b) => a.date.compareTo(b.date));
    final cats = {...widget.recommended.keys, ...widget.planned.keys}.toList()..sort();
    final filterActive = filtreDate != null || filtreMotCle.trim().isNotEmpty;

    return Column(
      children: [
        AppBar(
          title: const Text('Plan de la semaine'),
          actions: [
            IconButton(onPressed: widget.onEditCapacity, icon: const Icon(Icons.tune), tooltip: 'Disponibilité par jour'),
            IconButton(onPressed: widget.onOpenRoutine, icon: const Icon(Icons.repeat), tooltip: 'Ma routine'),
            IconButton(onPressed: widget.onPropose, icon: const Icon(Icons.auto_awesome), tooltip: 'Proposer un planning'),
            IconButton(onPressed: widget.onClear, icon: const Icon(Icons.playlist_remove), tooltip: 'Effacer le planning'),
            IconButton(onPressed: widget.onAdd, icon: const Icon(Icons.add)),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statTile(
                      c,
                      icon: Icons.timer_outlined,
                      label: 'Pratiqué cette semaine',
                      value: '${widget.minutes ~/ 60}h${(widget.minutes % 60).toString().padLeft(2, '0')} / ${widget.weeklyTarget ~/ 60}h${(widget.weeklyTarget % 60).toString().padLeft(2, '0')}',
                    ),
                    const SizedBox(height: 12),
                    progress((widget.minutes / widget.weeklyTarget).clamp(0, 1).toDouble()),
                    if (cats.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _sectionHeader(c, Icons.pie_chart_outline, 'Répartition recommandée vs planifiée',
                        subtitle: 'Basée sur l\'avancement de tes morceaux : les moins avancés (et les morceaux prioritaires) reçoivent plus de temps.'),
                      const SizedBox(height: 14),
                      ...(() {
                        final sharedMax = cats
                            .map((cat) => [widget.planned[cat] ?? 0, widget.recommended[cat] ?? 0].reduce((a, b) => a > b ? a : b))
                            .fold<int>(1, (a, b) => b > a ? b : a);
                        return cats.map((cat) => categoryComparisonRow(cat, widget.planned[cat] ?? 0, widget.recommended[cat] ?? 0, sharedMax));
                      })(),
                    ],
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: widget.onPropose,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Proposer un planning'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: _sectionHeader(c, Icons.filter_alt_outlined, 'Filtrer les séances')),
                      if (filterActive)
                        TextButton(
                          onPressed: () => setState(() {
                            filtreDate = null;
                            filtreMotCle = '';
                          }),
                          child: const Text('Réinitialiser'),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: c,
                            initialDate: filtreDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setState(() => filtreDate = picked);
                        },
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: Text(filtreDate == null ? 'Date spécifique' : '${filtreDate!.day}/${filtreDate!.month}/${filtreDate!.year}'),
                      ),
                      if (filtreDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Effacer le filtre de date',
                          onPressed: () => setState(() => filtreDate = null),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Rechercher (mot-clé, titre, catégorie, méthode)',
                        prefixIcon: Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => filtreMotCle = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (sorted.isEmpty)
                emptyState(filterActive
                    ? 'Aucune séance ne correspond à ce filtre.'
                    : 'Aucune séance planifiée.\nAppuie sur + ou sur la baguette magique pour en ajouter.')
              else
                ...groupedByDay(sorted).entries.expand((entry) => [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          '${weekday(entry.key.weekday)} ${entry.key.day}/${entry.key.month}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                        ),
                      ),
                      ...entry.value.map((x) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: swipeToDelete(
                              key: ValueKey(x.id),
                              what: 'cette séance',
                              onDelete: () => widget.onDelete(x),
                              child: CardBox(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: (x.completed ? Colors.green : categoryColor(x.category)).withOpacity(.12),
                                      ),
                                      child: IconButton(
                                        onPressed: () => widget.onToggle(x),
                                        icon: Icon(x.completed ? Icons.check_circle : Icons.circle_outlined),
                                        iconSize: x.completed ? 30 : 24,
                                        color: x.completed ? Colors.green.shade600 : categoryColor(x.category),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => widget.onEdit(x),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(20),
                                                  color: (x.completed ? Colors.grey : categoryColor(x.category)).withOpacity(.14),
                                                ),
                                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                  Icon(categoryIcon(x.category), size: 13, color: x.completed ? Colors.grey : categoryColor(x.category)),
                                                  const SizedBox(width: 4),
                                                  Text(x.category ?? 'Non catégorisé', style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: x.completed ? Colors.grey : categoryColor(x.category),
                                                    decoration: x.completed ? TextDecoration.lineThrough : null,
                                                  )),
                                                ]),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(x.title, style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: x.completed ? Colors.grey : null,
                                                decoration: x.completed ? TextDecoration.lineThrough : null,
                                              )),
                                              if (x.details.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(x.details, style: TextStyle(
                                                  color: Colors.grey,
                                                  decoration: x.completed ? TextDecoration.lineThrough : null,
                                                )),
                                              ],
                                              if (x.duration > 0 || x.method != null) ...[
                                                const SizedBox(height: 6),
                                                Wrap(spacing: 6, runSpacing: 6, children: [
                                                  if (x.duration > 0)
                                                    Chip(
                                                      visualDensity: VisualDensity.compact,
                                                      avatar: Icon(Icons.timer_outlined, size: 14, color: x.completed ? Colors.grey : null),
                                                      label: Text('${x.duration} min', style: TextStyle(
                                                        fontSize: 11,
                                                        color: x.completed ? Colors.grey : null,
                                                        decoration: x.completed ? TextDecoration.lineThrough : null,
                                                      )),
                                                    ),
                                                  if (x.method != null)
                                                    Chip(
                                                      visualDensity: VisualDensity.compact,
                                                      avatar: Icon(Icons.smartphone, size: 14, color: x.completed ? Colors.grey : null),
                                                      label: Text(x.method!, style: TextStyle(
                                                        fontSize: 11,
                                                        color: x.completed ? Colors.grey : null,
                                                        decoration: x.completed ? TextDecoration.lineThrough : null,
                                                      )),
                                                    ),
                                                ]),
                                              ],
                                            if (!x.completed) ...[
                                              const SizedBox(height: 6),
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: FilledButton.tonalIcon(
                                                  onPressed: () => widget.onStartTimer(x),
                                                  icon: const Icon(Icons.play_arrow, size: 18),
                                                  label: const Text('Démarrer'),
                                                  style: FilledButton.styleFrom(
                                                    visualDensity: VisualDensity.compact,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (x.motsCles.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: x.motsCles
                                                    .map((tag) => Chip(
                                                          visualDensity: VisualDensity.compact,
                                                          label: Text(tag, style: const TextStyle(fontSize: 11)),
                                                        ))
                                                    .toList(),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20),
                                      tooltip: 'Supprimer',
                                      onPressed: () async {
                                        if (await confirmDelete(c, 'cette séance')) widget.onDelete(x);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )),
                    ]),
            ],
          ),
        ),
      ],
    );
  }

  Map<DateTime, List<PlanItem>> groupedByDay(List<PlanItem> sorted) {
    final map = <DateTime, List<PlanItem>>{};
    for (final x in sorted) {
      final key = DateTime(x.date.year, x.date.month, x.date.day);
      map.putIfAbsent(key, () => []).add(x);
    }
    return map;
  }
}

Widget categoryComparisonRow(String cat, int plannedMin, int targetMin, int sharedMax) {
  final maxVal = sharedMax.toDouble();
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(categoryIcon(cat), size: 16, color: categoryColor(cat)),
            const SizedBox(width: 6),
            Expanded(child: Text(cat, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            Text('$plannedMin / $targetMin min', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: categoryColor(cat).withOpacity(.12)),
                FractionallySizedBox(
                  widthFactor: (targetMin / maxVal).clamp(0, 1),
                  child: Container(color: categoryColor(cat).withOpacity(.35)),
                ),
                FractionallySizedBox(
                  widthFactor: (plannedMin / maxVal).clamp(0, 1),
                  child: Container(color: categoryColor(cat)),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Ma routine ("journée type")
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Bilan hebdomadaire
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Badges
// ---------------------------------------------------------------------------

class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key, required this.badges});
  final List<AppBadge> badges;

  @override
  Widget build(BuildContext c) {
    final earnedCount = badges.where((b) => b.earned).length;
    return Scaffold(
      appBar: AppBar(title: Text('Badges ($earnedCount/${badges.length})')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: badges.length,
        itemBuilder: (_, i) {
          final b = badges[i];
          return CardBox(
            child: Opacity(
              opacity: b.earned ? 1 : 0.35,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(b.emoji, style: const TextStyle(fontSize: 34)),
                  const SizedBox(height: 8),
                  Text(
                    b.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  if (!b.earned) ...[
                    const SizedBox(height: 6),
                    const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class BilanScreen extends StatefulWidget {
  const BilanScreen({super.key, required this.currentBilan, required this.weeklyHistory, required this.onFocusNextWeek});
  final WeeklyBilan currentBilan;
  final List<WeeklyBilan> Function({int weeks}) weeklyHistory;
  final void Function(String category) onFocusNextWeek;

  @override
  State<BilanScreen> createState() => _BilanScreenState();
}

class _BilanScreenState extends State<BilanScreen> {
  bool showHistory = false;
  int selectedWeeks = 12;

  static const _weekdayNamesFull = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      appBar: AppBar(title: Text(showHistory ? 'Historique de pratique' : 'Bilan de la semaine')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Cette semaine')),
                ButtonSegment(value: true, label: Text('Historique')),
              ],
              selected: {showHistory},
              onSelectionChanged: (v) => setState(() => showHistory = v.first),
            ),
          ),
          Expanded(child: showHistory ? _buildHistory(c) : _buildCurrentWeek(c)),
        ],
      ),
    );
  }

  Widget _buildCurrentWeek(BuildContext c) {
    final bilan = widget.currentBilan;
    final start = bilan.weekStart;
    final end = start.add(const Duration(days: 6));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('${start.day}/${start.month} → ${end.day}/${end.month}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        CardBox(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52, height: 52, alignment: Alignment.center,
                decoration: BoxDecoration(color: Theme.of(c).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.timer_outlined, size: 26, color: Theme.of(c).colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Temps pratiqué', style: TextStyle(fontSize: 13, color: Theme.of(c).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  Text(
                    '${bilan.totalMinutes ~/ 60}h${(bilan.totalMinutes % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (bilan.pieces.isNotEmpty)
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(c, Icons.music_note_outlined,
                  '${bilan.pieces.length} morceau${bilan.pieces.length > 1 ? 'x' : ''} travaillé${bilan.pieces.length > 1 ? 's' : ''}'),
                const SizedBox(height: 14),
                for (final e in bilan.pieces)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(e.key.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text('${e.value} min', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 4),
                        progress(e.key.progress),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: _statTile(c,
              icon: Icons.emoji_events_outlined,
              label: 'Meilleur jour',
              value: bilan.bestDay != null ? _weekdayNamesFull[bilan.bestDay!.weekday - 1] : '—',
              sub: bilan.bestDay != null ? '${bilan.bestDayMinutes} min' : null,
              accent: Colors.amber.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statTile(c,
              icon: Icons.calendar_month_outlined,
              label: 'Jours pratiqués',
              value: '${bilan.daysPracticed} / 7',
            ),
          ),
        ]),
        if (bilan.avgRating != null) ...[
          const SizedBox(height: 16),
          CardBox(
            child: Row(children: [
              Container(
                width: 38, height: 38, alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.amber.withOpacity(.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.star_rounded, size: 20, color: Colors.amber),
              ),
              const SizedBox(width: 11),
              const Expanded(child: Text('Ressenti moyen de la semaine', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('★' * bilan.avgRating!.round(), style: const TextStyle(color: Colors.amber, fontSize: 16)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(c, Icons.flag_outlined, 'Orienter la semaine prochaine',
                subtitle: 'Ajoute une priorité à tes consignes de planning pour la prochaine génération.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: objectiveCategories
                    .map((cat) => ActionChip(
                          avatar: Icon(categoryIcon(cat), size: 16, color: categoryColor(cat)),
                          label: Text(cat),
                          onPressed: () {
                            widget.onFocusNextWeek(cat);
                            ScaffoldMessenger.of(c).showSnackBar(
                              SnackBar(content: Text('Ajouté aux consignes de planning : "priorité $cat"')),
                            );
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistory(BuildContext c) {
    final history = widget.weeklyHistory(weeks: selectedWeeks);
    if (history.length < 2) {
      // Pas encore assez de semaines de pratique enregistrees pour qu'un historique ait du sens.
      return emptyState('Reviens ici dans quelques semaines : l\'historique se construit au fil de tes sessions.');
    }

    final totalMinutes = history.fold(0, (a, w) => a + w.totalMinutes);
    final avgPerWeek = totalMinutes / history.length;
    final maxMinutes = history.fold(0, (a, w) => w.totalMinutes > a ? w.totalMinutes : a);
    // Compare la 2e moitie de la periode a la 1ere pour degager une tendance simple.
    final half = history.length ~/ 2;
    final firstHalfAvg = history.take(half).fold(0, (a, w) => a + w.totalMinutes) / half;
    final secondHalfAvg = history.skip(history.length - half).fold(0, (a, w) => a + w.totalMinutes) / half;
    final trendUp = secondHalfAvg > firstHalfAvg * 1.05;
    final trendDown = secondHalfAvg < firstHalfAvg * 0.95;

    // Top morceaux de la periode, agreges a partir des bilans hebdomadaires deja calcules.
    final totalByProject = <String, int>{};
    final weeklyByProject = <String, List<int>>{};
    for (var i = 0; i < history.length; i++) {
      for (final e in history[i].pieces) {
        final id = e.key.id;
        totalByProject[id] = (totalByProject[id] ?? 0) + e.value;
        weeklyByProject.putIfAbsent(id, () => List.filled(history.length, 0))[i] = e.value;
      }
    }
    final topProjectIds = totalByProject.keys.toList()..sort((a, b) => totalByProject[b]!.compareTo(totalByProject[a]!));
    final topProjects = topProjectIds.take(5).toList();
    final projectById = <String, Project>{
      for (final w in history) for (final e in w.pieces) e.key.id: e.key,
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4 sem.')),
              ButtonSegment(value: 8, label: Text('8 sem.')),
              ButtonSegment(value: 12, label: Text('12 sem.')),
              ButtonSegment(value: 26, label: Text('26 sem.')),
            ],
            selected: {selectedWeeks},
            onSelectionChanged: (v) => setState(() => selectedWeeks = v.first),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: _statTile(c,
              icon: Icons.bar_chart_outlined,
              label: 'Moyenne / semaine',
              value: '${avgPerWeek ~/ 60}h${(avgPerWeek % 60).round().toString().padLeft(2, '0')}',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statTile(c,
              icon: trendUp ? Icons.trending_up : (trendDown ? Icons.trending_down : Icons.trending_flat),
              label: 'Tendance',
              value: trendUp ? 'En hausse' : (trendDown ? 'En baisse' : 'Stable'),
              accent: trendUp ? Colors.green.shade600 : (trendDown ? Colors.deepOrange : Colors.grey),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(c, Icons.show_chart, 'Minutes pratiquées par semaine'),
              const SizedBox(height: 16),
              SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final w in history)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Tooltip(
                            message: '${w.weekStart.day}/${w.weekStart.month} : ${w.totalMinutes} min',
                            child: Builder(builder: (_) {
                              final ratio = maxMinutes > 0 ? (w.totalMinutes / maxMinutes).clamp(0.02, 1.0).toDouble() : 0.02;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  SizedBox(
                                    height: 100,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: FractionallySizedBox(
                                        heightFactor: ratio,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: w.weekStart == history.last.weekStart
                                                ? Theme.of(c).colorScheme.primary
                                                : Theme.of(c).colorScheme.primary.withOpacity(.35),
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${w.weekStart.day}/${w.weekStart.month}',
                                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (topProjects.isNotEmpty) ...[
          const SizedBox(height: 16),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(c, Icons.pie_chart_outline, 'Répartition par morceau',
                  subtitle: 'Sur les $selectedWeeks dernières semaines'),
                const SizedBox(height: 14),
                for (final id in topProjects)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(projectById[id]?.emoji ?? '🎵'),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              projectById[id]?.name ?? 'Morceau supprimé',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${totalByProject[id]} min',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 28,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final m in weeklyByProject[id]!)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 1),
                                    child: Builder(builder: (_) {
                                      final ratio = maxMinutes > 0
                                          ? (m / maxMinutes).clamp(m > 0 ? 0.06 : 0.0, 1.0).toDouble()
                                          : 0.0;
                                      return Align(
                                        alignment: Alignment.bottomCenter,
                                        child: FractionallySizedBox(
                                          heightFactor: ratio,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: categoryColor(projectById[id]?.weakestCategory),
                                              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Courbe de progression du tempo (BPM) d'un morceau dans le temps, construite a partir
/// des releves de tempo saisis apres chaque session (voir Session.newTempo). Chaque point
/// correspond a une session ou le tempo a ete explicitement renseigne : les sessions sans
/// tempo saisi n'apparaissent pas, evitant de fausser la courbe avec des zeros.
class TempoHistoryScreen extends StatelessWidget {
  const TempoHistoryScreen({super.key, required this.projectName, required this.targetTempo, required this.entries});
  final String projectName;
  final int targetTempo;
  final List<MapEntry<DateTime, int>> entries; // triees par date croissante

  @override
  Widget build(BuildContext c) {
    if (entries.length < 2) {
      return Scaffold(
        appBar: AppBar(title: Text('Tempo — $projectName')),
        body: emptyState(
          entries.isEmpty
              ? 'Renseigne le tempo atteint après une session pour commencer à suivre sa progression.'
              : 'Encore un relevé et la courbe pourra apparaître.',
        ),
      );
    }

    final maxValue = [targetTempo, ...entries.map((e) => e.value)].reduce((a, b) => a > b ? a : b);
    final first = entries.first.value;
    final last = entries.last.value;
    final gained = last - first;

    return Scaffold(
      appBar: AppBar(title: Text('Tempo — $projectName')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            Expanded(
              child: _statTile(c,
                icon: Icons.speed_outlined,
                label: 'Tempo actuel',
                value: '$last BPM',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statTile(c,
                icon: gained > 0 ? Icons.trending_up : (gained < 0 ? Icons.trending_down : Icons.trending_flat),
                label: 'Depuis le premier relevé',
                value: '${gained > 0 ? '+' : ''}$gained BPM',
                accent: gained > 0 ? Colors.green.shade600 : (gained < 0 ? Colors.deepOrange : Colors.grey),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(c, Icons.show_chart, 'Évolution du tempo',
                  subtitle: targetTempo > 0 ? 'Ligne repère : objectif à $targetTempo BPM' : null),
                const SizedBox(height: 16),
                // Rangee des valeurs, au-dessus de chaque barre.
                Row(
                  children: [
                    for (final e in entries)
                      Expanded(
                        child: Text(
                          '${e.value}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Zone de tracé : exactement 90px, partagee par les barres et la ligne repere
                // du tempo cible, pour que les deux soient positionnees sur la meme echelle.
                SizedBox(
                  height: 90,
                  child: Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final e in entries)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: Builder(builder: (_) {
                                  final ratio = maxValue > 0 ? (e.value / maxValue).clamp(0.04, 1.0).toDouble() : 0.04;
                                  return Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: ratio,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: e.key == entries.last.key ? Colors.teal : Colors.teal.withOpacity(.45),
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                        ],
                      ),
                      if (targetTempo > 0 && maxValue > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 90 * (1 - (targetTempo / maxValue).clamp(0.0, 1.0).toDouble()),
                          child: Container(height: 2, color: Colors.amber.withOpacity(.7)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Rangee des dates, sous chaque barre.
                Row(
                  children: [
                    for (final e in entries)
                      Expanded(
                        child: Text(
                          '${e.key.day}/${e.key.month}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Détail des relevés', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                for (final e in entries.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(child: Text('${e.key.day}/${e.key.month}/${e.key.year}')),
                      Text('${e.value} BPM', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MethodsScreen extends StatelessWidget {
  const MethodsScreen({super.key, required this.methods, required this.onAdd, required this.onEdit, required this.onDelete});
  final List<MethodDefinition> methods;
  final VoidCallback onAdd;
  final void Function(MethodDefinition) onEdit;
  final void Function(MethodDefinition) onDelete;
  @override Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Méthodes'), actions: [IconButton(onPressed: onAdd, icon: const Icon(Icons.add))]),
    body: methods.isEmpty ? Center(child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Créer une méthode'))) : ListView.separated(
      padding: const EdgeInsets.all(16), itemCount: methods.length, separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) { final m = methods[i]; return CardBox(child: Theme(
        data: Theme.of(c).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 10),
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          leading: Container(
            width: 38, height: 38, alignment: Alignment.center,
            decoration: BoxDecoration(color: Theme.of(c).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.menu_book_outlined, size: 18, color: Theme.of(c).colorScheme.primary),
          ),
          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${m.level} · ${m.durationMinutes} min', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 12)),
        children: [
          if (m.description.isNotEmpty) _info(c, 'Description', m.description),
          if (m.objectives.isNotEmpty) _info(c, 'Objectifs', m.objectives),
          if (m.exercises.isNotEmpty) _info(c, 'Exercices / déroulé', m.exercises),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton.icon(onPressed: () => onEdit(m), icon: const Icon(Icons.edit_outlined), label: const Text('Modifier')), TextButton.icon(onPressed: () => onDelete(m), icon: const Icon(Icons.delete_outline), label: const Text('Supprimer'))]),
        ],
      ))); },
    ),
    floatingActionButton: FloatingActionButton(onPressed: onAdd, child: const Icon(Icons.add)),
  );
  static Widget _info(BuildContext c, String title, String value) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant)), const SizedBox(height: 3), Text(value)])));
}

class RoutineScreen extends StatelessWidget {
  const RoutineScreen({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onMove,
    required this.onGenerate,
  });
  final List<RoutineItem> items;
  final VoidCallback onAdd;
  final void Function(RoutineItem) onEdit;
  final void Function(RoutineItem) onDelete;
  final void Function(RoutineItem, int) onMove;
  final VoidCallback onGenerate;

  static const _routineColors = [
    Colors.purple, Colors.red, Colors.blue, Colors.brown, Colors.pink,
    Colors.indigo, Colors.green, Colors.blueGrey, Colors.teal, Colors.deepOrange,
  ];

  String _summary(RoutineItem item) {
    final freq = item.cadence == 'jour'
        ? '${item.count}× · ${_PianoPracticeAppState.daysLabel(item.days)}'
        : '${item.count}× par semaine';
    final duration = item.fixedMinutes != null
        ? ' · ${item.fixedMinutes} min fixes'
        : item.maxMinutes != null
            ? ' · max ${item.maxMinutes} min'
            : '';
    return '$freq$duration';
  }

  @override
  Widget build(BuildContext c) {
    final sorted = [...items]..sort((a, b) => a.order.compareTo(b.order));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma routine'),
        actions: [IconButton(onPressed: onAdd, icon: const Icon(Icons.add))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Générer le planning'),
            ),
          ),
          Expanded(
            child: sorted.isEmpty
                ? emptyState('Aucune entrée pour l\'instant.\nAppuie sur + pour définir ta journée type.')
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final item = sorted[i];
                      final color = _routineColors[i % _routineColors.length];
                      return swipeToDelete(
                        key: ValueKey(item.id),
                        what: 'cette entrée',
                        onDelete: () => onDelete(item),
                        child: CardBox(
                          child: InkWell(
                            onTap: () => onEdit(item),
                            child: Row(
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                                      onPressed: i == 0 ? null : () => onMove(item, -1),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                                      onPressed: i == sorted.length - 1 ? null : () => onMove(item, 1),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  width: 34, height: 34, alignment: Alignment.center,
                                  decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(11)),
                                  child: Icon(Icons.repeat, size: 16, color: color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Text(_summary(item), style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Supprimer cette routine',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => onDelete(item),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class RoutineDialog extends StatefulWidget {
  const RoutineDialog({super.key, this.existing});
  final RoutineItem? existing;
  @override
  State<RoutineDialog> createState() => _RoutineDialogState();
}

class _RoutineDialogState extends State<RoutineDialog> {
  late TextEditingController labelCtrl;
  int count = 1;
  String cadence = 'semaine';
  late List<int> days;
  String durationMode = 'auto'; // 'auto' | 'fixe' | 'max'
  int durationMinutes = 20;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    labelCtrl = TextEditingController(text: e?.label ?? '');
    count = e?.count ?? 1;
    cadence = e?.cadence ?? 'semaine';
    days = [...(e?.days ?? [1, 2, 3, 4, 5, 6, 7])];
    if (e?.fixedMinutes != null) {
      durationMode = 'fixe';
      durationMinutes = e!.fixedMinutes!;
    } else if (e?.maxMinutes != null) {
      durationMode = 'max';
      durationMinutes = e!.maxMinutes!;
    } else {
      durationMode = 'auto';
      durationMinutes = 20;
    }
  }

  @override
  void dispose() {
    labelCtrl.dispose();
    super.dispose();
  }

  void _setDays(List<int> d) => setState(() => days = d);

  @override
  Widget build(BuildContext c) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier l\'entrée' : 'Nouvelle entrée de routine'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Nom (ex: Technique + nouveau travail)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(children: [
              const Text('Fréquence :'),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: count <= 1 ? null : () => setState(() => count--),
              ),
              Text('$count×', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => count++),
              ),
            ]),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'jour', label: Text('Jour(s) précis')),
                ButtonSegment(value: 'semaine', label: Text('Quelque part dans la semaine')),
              ],
              selected: {cadence},
              onSelectionChanged: (v) => setState(() => cadence = v.first),
            ),
            if (cadence == 'jour') ...[
              const SizedBox(height: 14),
              Wrap(spacing: 6, children: [
                OutlinedButton(onPressed: () => _setDays([1, 2, 3, 4, 5, 6, 7]), child: const Text('Tous les jours')),
                OutlinedButton(onPressed: () => _setDays([1, 2, 3, 4, 5]), child: const Text('Semaine')),
                OutlinedButton(onPressed: () => _setDays([6, 7]), child: const Text('Week-end')),
              ]),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(7, (i) {
                  final d = i + 1;
                  final selected = days.contains(d);
                  return FilterChip(
                    label: Text(_PianoPracticeAppState._dayLabels[i]),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        days.add(d);
                      } else {
                        days.remove(d);
                      }
                    }),
                  );
                }),
              ),
            ],
            const SizedBox(height: 14),
            const Align(alignment: Alignment.centerLeft, child: Text('Durée', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text('Automatique')),
                ButtonSegment(value: 'fixe', label: Text('Fixe (protégée)')),
                ButtonSegment(value: 'max', label: Text('Plafonnée')),
              ],
              selected: {durationMode},
              onSelectionChanged: (v) => setState(() => durationMode = v.first),
            ),
            const SizedBox(height: 6),
            Text(
              switch (durationMode) {
                'fixe' => 'Reçoit toujours exactement cette durée en premier, avant tout le reste (ex: un rituel de 15-20 min).',
                'max' => 'Ne dépasse jamais cette durée, même si elle serait autrement plus grande — le reste profite au planning des morceaux.',
                _ => 'Se partage le temps restant du jour avec le reste, sans limite propre — peut prendre beaucoup de place si peu d\'autres entrées ce jour-là.',
              },
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (durationMode != 'auto') ...[
              const SizedBox(height: 10),
              Row(children: [
                const Text('Durée :'),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: durationMinutes <= 5 ? null : () => setState(() => durationMinutes -= 5),
                ),
                Text('$durationMinutes min', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => durationMinutes += 5),
                ),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(
          onPressed: labelCtrl.text.trim().isEmpty || (cadence == 'jour' && days.isEmpty)
              ? null
              : () => Navigator.pop(
                    c,
                    RoutineItem(
                      id: widget.existing?.id ?? newId(),
                      label: labelCtrl.text.trim(),
                      count: count,
                      cadence: cadence,
                      days: days,
                      fixedMinutes: durationMode == 'fixe' ? durationMinutes : null,
                      maxMinutes: durationMode == 'max' ? durationMinutes : null,
                      order: widget.existing?.order ?? 0,
                    ),
                  ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class PlanDialog extends StatefulWidget {
  const PlanDialog({super.key, required this.projects, this.existing});
  final List<Project> projects;
  final PlanItem? existing;
  @override
  State<PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<PlanDialog> {
  late DateTime date;
  late TextEditingController titleCtrl;
  late TextEditingController detailsCtrl;
  late TextEditingController durationCtrl;
  late TextEditingController tagsCtrl;
  String title = '';
  int duration = 30;
  Project? project;
  String? category;
  String? method;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    date = e?.date ?? DateTime.now();
    title = e?.title ?? '';
    duration = e?.duration ?? 30;
    category = e?.category;
    method = e?.method;
    titleCtrl = TextEditingController(text: title);
    detailsCtrl = TextEditingController(text: e?.details ?? '');
    durationCtrl = TextEditingController(text: duration.toString());
    tagsCtrl = TextEditingController(text: e?.motsCles.join(', ') ?? '');
    project = e == null ? null : widget.projects.where((p) => p.id == e.projectId).firstOrNull;
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    detailsCtrl.dispose();
    durationCtrl.dispose();
    tagsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier la séance' : 'Planifier une séance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Jour : ${date.day}/${date.month}/${date.year}'),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final d = await showDatePicker(
                  context: c,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: date,
                );
                if (d != null) setState(() => date = d);
              },
            ),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Travail prévu'),
              onChanged: (v) => setState(() => title = v),
            ),
            TextField(controller: detailsCtrl, decoration: const InputDecoration(labelText: 'Détails')),
            TextField(
              controller: durationCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Durée (minutes)'),
              onChanged: (v) => setState(() => duration = int.tryParse(v) ?? duration),
            ),
            DropdownButtonFormField<String?>(
              value: category,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Non catégorisé')),
                ...objectiveCategories.map((v) => DropdownMenuItem(value: v, child: Text(v))),
              ],
              onChanged: (v) => setState(() => category = v),
            ),
            DropdownButtonFormField<String?>(
              value: method,
              decoration: const InputDecoration(labelText: 'Application / méthode'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Aucune')),
                ...learningMethods.map((v) => DropdownMenuItem(value: v, child: Text(v))),
              ],
              onChanged: (v) => setState(() => method = v),
            ),
            DropdownButtonFormField<Project?>(
              value: project,
              decoration: const InputDecoration(labelText: 'Morceau'),
              items: projectItems(widget.projects),
              onChanged: (v) => setState(() => project = v),
            ),
            TextField(
              controller: tagsCtrl,
              decoration: const InputDecoration(
                labelText: 'Mots-clés (séparés par des virgules)',
                hintText: 'ex: Urgent, VIP',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        FilledButton(
          onPressed: title.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    c,
                    PlanItem(
                      id: widget.existing?.id ?? newId(),
                      date: date,
                      duration: duration,
                      title: title,
                      details: detailsCtrl.text,
                      projectId: project?.id,
                      category: category,
                      method: method,
                      completed: widget.existing?.completed ?? false,
                      motsCles: tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
                    ),
                  ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
