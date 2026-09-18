// V155 — journal coach : date de l'ajustement + bon morceau concerné.
// V154 — maîtrise des morceaux + adaptation charge/variété + clarté Coach/Planning.
// V153 — coche verte pour les séances réalisées, sans réactivation.
// V151 — COACH toujours visible + analyse récente intégrée au planning.
// V150 — coach explicable : morceaux à faire avancer + analyse récente du coach.
// Base fonctionnelle : V134 -> V145 -> V146 -> V147.
// V120 — coach adaptatif : le planning apprend du temps réellement joué.
// V119 — ergonomie des détails : hiérarchie plus nette, cartes internes allégées.
// V118 — maîtrise morceau : progression globale + tempo + continuité + stabilité.
// V117 — moteur coach fiabilisé : actions terminées écartées, rotation renforcée, charge adaptative.
// V115 — finition responsive iPhone, à partir de V114, sans changement fonctionnel.
// V89
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String appVersion = '155.0';

void main() => runApp(const PianoPracticeApp());

int _idCounter = 0;
String newId() {
  _idCounter += 1;
  return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
}

String _formatProjectDateTime(DateTime value) {
  if (value.millisecondsSinceEpoch <= 0) return '—';
  final local = value.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${local.year} à $hh:$min';
}

// V100 : en-têtes légers pour les écrans de détail, sans cartes imbriquées.
Widget _detailSectionHeader(BuildContext context, String title, {IconData? icon}) {
  return Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .3,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
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


// Besoin de travail actuel du morceau. 'Automatique' laisse le moteur utiliser
// les 4 étapes existantes pour déterminer le travail le plus utile.
const List<String> workFocuses = [
  'Automatique',
  'Déchiffrage',
  'Mains ensemble',
  'Rythme',
  'Accords',
  'Passages difficiles',
  'Mémorisation',
  'Interprétation',
  'Tempo',
  'Consolidation',
  'Entretien',
];

const List<String> workIntensities = ['Faible', 'Moyenne', 'Forte'];

String workFocusEmoji(String focus) {
  switch (focus) {
    case 'Déchiffrage': return '📖';
    case 'Mains ensemble': return '🤝';
    case 'Rythme': return '🥁';
    case 'Accords': return '🎹';
    case 'Passages difficiles': return '🎯';
    case 'Mémorisation': return '🧠';
    case 'Interprétation': return '🎭';
    case 'Tempo': return '⚡';
    case 'Consolidation': return '🔧';
    case 'Entretien': return '🎼';
    default: return '✨';
  }
}

int workFocusMaxMinutes(String focus) {
  switch (focus) {
    case 'Accords': return 20;
    case 'Rythme': return 20;
    case 'Passages difficiles': return 20;
    case 'Tempo': return 25;
    case 'Entretien': return 20;
    case 'Mémorisation': return 25;
    case 'Mains ensemble': return 30;
    case 'Déchiffrage': return 30;
    case 'Interprétation': return 30;
    case 'Consolidation': return 25;
    default: return 40;
  }
}

int workFocusMinMinutes(String focus) {
  switch (focus) {
    case 'Accords': return 10;
    case 'Rythme': return 10;
    case 'Passages difficiles': return 10;
    case 'Tempo': return 10;
    case 'Entretien': return 10;
    case 'Consolidation': return 15;
    default: return 15;
  }
}

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
    this.workFocus = 'Automatique',
    this.workIntensity = 'Moyenne',
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
    DateTime? lastModified,
  }) : lastModified = lastModified ?? DateTime.now();
  final String id;
  String name;
  double progress;
  String goal;
  String? method;
  bool priority;
  String workFocus; // besoin de travail principal : automatique ou choisi
  String workIntensity; // Faible / Moyenne / Forte
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
  DateTime lastModified; // dernière modification de la fiche / du suivi du morceau

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'progress': progress,
        'goal': goal,
        'method': method,
        'priority': priority,
        'workFocus': workFocus,
        'workIntensity': workIntensity,
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
        'lastModified': lastModified.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        progress: (j['progress'] as num).toDouble(),
        goal: j['goal'] as String,
        method: j['method'] as String?,
        priority: j['priority'] as bool? ?? false,
        workFocus: workFocuses.contains(j['workFocus']) ? (j['workFocus'] as String) : 'Automatique',
        workIntensity: workIntensities.contains(j['workIntensity']) ? (j['workIntensity'] as String) : 'Moyenne',
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
        lastModified: j['lastModified'] is String
            ? (DateTime.tryParse(j['lastModified'] as String) ?? DateTime.fromMillisecondsSinceEpoch(0))
            : DateTime.fromMillisecondsSinceEpoch(0),
      );

  String get effectiveWorkFocus {
    if (workFocus != 'Automatique') return workFocus;
    final steps = <String, double>{
      'Déchiffrage': reading,
      'Mains ensemble': handsTogether,
      'Mémorisation': memory,
      'Interprétation': interpretation,
    };
    return steps.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

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
  String get weakestStageName {
    final values = {'Lecture': reading, 'Mains ensemble': handsTogether, 'Mémorisation': memory, 'Interprétation': interpretation};
    return values.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

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
    this.newReading,
    this.newHandsTogether,
    this.newMemory,
    this.newInterpretation,
    this.coachFeeling,
    this.coachFocus,
    this.coachRecommendation,
    this.plannedDuration,
    this.plannedTempo,
    this.runThroughCompleted,
    this.runThroughStopNote,
    this.runThroughStartTempo,
    this.runThroughEndTempo,
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

  // Etat des 4 etapes APRES cette session. Ces valeurs permettent de reconstruire
  // l'evolution reelle du morceau dans le temps, meme si l'avancement global est automatique.
  double? newReading;
  double? newHandsTogether;
  double? newMemory;
  double? newInterpretation;

  // Retour rapide donne par l'utilisateur a la fin de la session :
  // facile / correct / difficile. Utilise par le coach pour les prochaines recommandations.
  String? coachFeeling;
  String? coachFocus;
  String? coachRecommendation;

  // Planification coach d'origine : permet de comparer le prévu au réalisé.
  int? plannedDuration;
  int? plannedTempo;

  // Résultat spécifique du Run-through.
  bool? runThroughCompleted;
  String? runThroughStopNote;
  int? runThroughStartTempo;
  int? runThroughEndTempo;

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
        'newReading': newReading,
        'newHandsTogether': newHandsTogether,
        'newMemory': newMemory,
        'newInterpretation': newInterpretation,
        'coachFeeling': coachFeeling,
        'coachFocus': coachFocus,
        'coachRecommendation': coachRecommendation,
        'plannedDuration': plannedDuration,
        'plannedTempo': plannedTempo,
        'runThroughCompleted': runThroughCompleted,
        'runThroughStopNote': runThroughStopNote,
        'runThroughStartTempo': runThroughStartTempo,
        'runThroughEndTempo': runThroughEndTempo,
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
        newReading: (j['newReading'] as num?)?.toDouble(),
        newHandsTogether: (j['newHandsTogether'] as num?)?.toDouble(),
        newMemory: (j['newMemory'] as num?)?.toDouble(),
        newInterpretation: (j['newInterpretation'] as num?)?.toDouble(),
        coachFeeling: j['coachFeeling'] as String?,
        coachFocus: j['coachFocus'] as String?,
        coachRecommendation: j['coachRecommendation'] as String?,
        plannedDuration: (j['plannedDuration'] as num?)?.toInt() ?? (j['duration'] as num?)?.toInt() ?? 0,
        plannedTempo: (j['plannedTempo'] as num?)?.toInt(),
        runThroughCompleted: j['runThroughCompleted'] as bool?,
        runThroughStopNote: j['runThroughStopNote'] as String?,
        runThroughStartTempo: (j['runThroughStartTempo'] as num?)?.toInt(),
        runThroughEndTempo: (j['runThroughEndTempo'] as num?)?.toInt(),
      );
}

String runThroughResultLabel(Session s, Project? p) {
  if (s.type != 'Run-through' || s.runThroughCompleted == null) return '';
  if (!s.runThroughCompleted!) return '⏹️ Interrompu';
  final target = p?.targetTempo ?? 0;
  final end = s.runThroughEndTempo ?? 0;
  if (target > 0 && end > 0) {
    final ratio = end / target;
    if (ratio >= 1.0) return '✅ Terminé · tempo cible atteint';
    if (ratio >= 0.9) return '✅ Terminé · proche du tempo cible';
    return '✅ Terminé · tempo encore à construire';
  }
  return '✅ Terminé';
}

double runThroughMasteryScore(Project p, List<Session> sessions) {
  final runs = sessions
      .where((s) => s.type == 'Run-through' && s.runThroughCompleted == true)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  if (runs.isEmpty) return 0;

  final latest = runs.first;
  final end = latest.runThroughEndTempo ?? 0;
  final start = latest.runThroughStartTempo ?? 0;
  final tempoScore = p.targetTempo > 0 && end > 0
      ? (end / p.targetTempo).clamp(0.0, 1.0)
      : 1.0;
  final continuityScore = latest.runThroughCompleted == true ? 1.0 : 0.0;
  final stabilityScore = start > 0 && end > 0
      ? (end / start).clamp(0.0, 1.0)
      : 0.80;
  return ((tempoScore * .55 + continuityScore * .25 + stabilityScore * .20) * 100).roundToDouble();
}

double pieceMasteryScore(Project p, List<Session> sessions) {
  final stageAverage = ((p.reading + p.handsTogether + p.memory + p.interpretation) / 4).clamp(0.0, 1.0);
  final tempoScore = p.targetTempo > 0 && p.currentTempo > 0
      ? (p.currentTempo / p.targetTempo).clamp(0.0, 1.0)
      : stageAverage;
  final runScore = runThroughMasteryScore(p, sessions) / 100.0;
  final runWeight = sessions.any((s) => s.type == 'Run-through' && s.runThroughCompleted != null) ? .25 : 0.0;
  final baseWeight = 1.0 - runWeight;
  final score = stageAverage * (baseWeight * .68) + tempoScore * (baseWeight * .32) + runScore * runWeight;
  return (score.clamp(0.0, 1.0) * 100).toDouble();
}

String masteryLabel(double score) {
  if (score >= 90) return 'Maîtrise solide';
  if (score >= 75) return 'Bien maîtrisé';
  if (score >= 60) return 'En consolidation';
  if (score >= 40) return 'En construction';
  return 'À construire';
}

class CoachDecision {
  CoachDecision({
    required this.id,
    required this.date,
    required this.sessionId,
    required this.projectId,
    required this.changed,
    required this.title,
    required this.message,
    this.oldDuration,
    this.newDuration,
    this.reason,
    this.adjustedPlanItemId,
    this.adjustedProjectId,
    this.adjustedPlanDate,
  });

  final String id;
  final DateTime date;
  final String sessionId;
  /// Morceau de la séance analysée.
  final String? projectId;
  final bool changed;
  final String title;
  final String message;
  final int? oldDuration;
  final int? newDuration;
  final String? reason;
  /// Morceau réellement modifié dans le planning, qui peut être différent
  /// du morceau de la séance analysée.
  final String? adjustedPlanItemId;
  final String? adjustedProjectId;
  final DateTime? adjustedPlanDate;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'sessionId': sessionId,
        'projectId': projectId,
        'changed': changed,
        'title': title,
        'message': message,
        'oldDuration': oldDuration,
        'newDuration': newDuration,
        'reason': reason,
        'adjustedPlanItemId': adjustedPlanItemId,
        'adjustedProjectId': adjustedProjectId,
        'adjustedPlanDate': adjustedPlanDate?.toIso8601String(),
      };

  factory CoachDecision.fromJson(Map<String, dynamic> j) => CoachDecision(
        id: j['id'] as String? ?? newId(),
        date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
        sessionId: j['sessionId'] as String? ?? '',
        projectId: j['projectId'] as String?,
        changed: j['changed'] as bool? ?? false,
        title: j['title'] as String? ?? 'Analyse du coach',
        message: j['message'] as String? ?? '',
        oldDuration: (j['oldDuration'] as num?)?.toInt(),
        newDuration: (j['newDuration'] as num?)?.toInt(),
        reason: j['reason'] as String?,
        adjustedPlanItemId: j['adjustedPlanItemId'] as String?,
        adjustedProjectId: j['adjustedProjectId'] as String?,
        adjustedPlanDate: DateTime.tryParse(j['adjustedPlanDate']?.toString() ?? ''),
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
    int? plannedDuration,
    this.coachAdjusted = false,
    this.coachAdjustmentSeen = true,
    this.coachAdjustmentReason,
    this.coachAdjustedAt,
    this.coachPreviousDuration,
  }) : motsCles = motsCles ?? [], plannedDuration = plannedDuration ?? duration;
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
  final int plannedDuration; // durée prévue conservée après réalisation
  bool coachAdjusted; // le coach a modifié cette séance depuis sa création
  bool coachAdjustmentSeen; // l'utilisateur a consulté le détail de la modification
  String? coachAdjustmentReason; // explication courte de l'ajustement
  DateTime? coachAdjustedAt; // moment de la dernière décision du coach
  int? coachPreviousDuration; // durée avant la dernière décision, pour éviter les oscillations

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
        'plannedDuration': plannedDuration,
        'coachAdjusted': coachAdjusted,
        'coachAdjustmentSeen': coachAdjustmentSeen,
        'coachAdjustmentReason': coachAdjustmentReason,
        'coachAdjustedAt': coachAdjustedAt?.toIso8601String(),
        'coachPreviousDuration': coachPreviousDuration,
      };

  factory PlanItem.fromJson(Map<String, dynamic> j) {
    final duration = (j['duration'] as num?)?.toInt() ?? 0;
    final planned = (j['plannedDuration'] as num?)?.toInt() ?? duration;
    final completed = j['completed'] as bool? ?? false;
    final sourceSessionId = j['sourceSessionId'] as String?;
    return PlanItem(
      id: j['id'] as String,
      date: DateTime.parse(j['date'] as String),
      duration: duration,
      title: j['title'] as String,
      details: j['details'] as String,
      projectId: j['projectId'] as String?,
      category: j['category'] as String?,
      method: j['method'] as String?,
      completed: completed,
      motsCles: (j['motsCles'] as List?)?.map((e) => e as String).toList() ?? [],
      sourceSessionId: sourceSessionId,
      plannedDuration: planned,
      // Compatibilité avec les plannings V124 : si une séance future possède
      // déjà une durée différente de sa durée initiale, on la considère comme
      // une modification du coach, même si le nouveau champ n'existait pas.
      coachAdjusted: j['coachAdjusted'] as bool? ??
          (!completed && sourceSessionId == null && planned > 0 && duration != planned),
      coachAdjustmentSeen: j['coachAdjustmentSeen'] as bool? ?? true,
      coachAdjustmentReason: j['coachAdjustmentReason'] as String?,
      coachAdjustedAt: DateTime.tryParse(j['coachAdjustedAt']?.toString() ?? ''),
      coachPreviousDuration: (j['coachPreviousDuration'] as num?)?.toInt(),
    );
  }

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
  // V71/V72 : nombre de séances récentes ressenties comme difficiles pour un morceau.
  // Placé dans l'état principal car le moteur de planning y accède directement.
  // Dernier ressenti enregistré pour un morceau, utilisé par le moteur
  // d'adaptation du planning (V120).
  String? _lastFeeling(String projectId) {
    Session? last;
    for (final s in sessions) {
      if (s.projectId == projectId && (last == null || s.date.isAfter(last!.date))) {
        last = s;
      }
    }
    return last?.coachFeeling;
  }

  int _recentDifficultSessions(String projectId) {
    final recent = sessions
        .where((s) => s.projectId == projectId && s.coachFeeling != null)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return recent.take(3).where((s) => s.coachFeeling == 'difficile').length;
  }

  final navKey = GlobalKey<NavigatorState>();
  int tab = 0;
  bool loading = true;
  DateTime? lastBackupAt;
  bool _backupReminderShown = false;
  DateTime _clockNow = DateTime.now();
  Timer? _clockTimer;
  static const int _backupReminderDays = 7;
  List<int> dailyCapacity = [30, 30, 45, 30, 30, 45, 30]; // Lundi..Dimanche, en minutes
  String weeklyInstructions = ''; // criteres de planning saisis par l'utilisateur, conserves
  List<Project> projects = [];
  List<Session> sessions = [];
  List<PlanItem> plan = [];
  /// Jours volontairement laissés libres par la génération automatique du coach.
  /// Format : YYYY-MM-DD. Cela permet de distinguer un repos décidé par le coach
  /// d'une journée indisponible ou simplement non planifiée.
  Set<String> coachRestDayKeys = {};
  List<CoachDecision> coachDecisionLog = [];
  String? _lastCoachChangedItemId;
  int? _lastCoachOldDuration;
  int? _lastCoachNewDuration;
  String? _lastCoachReason;
  List<RoutineItem> routine = [];
  List<Challenge> challenges = [];
  bool darkMode = false;
  int bestStreakEver = 0;
  List<String> seenBadgeIds = [];
  // Référence utilisée pour permettre une vraie réinitialisation des badges :
  // les données de pratique sont conservées, mais les badges recommencent à
  // compter à partir de cette référence.
  int badgeBaselineMinutes = 0;
  int badgeBaselineSessions = 0;
  int badgeBaselinePieces = 0;
  int badgeBaselineChallenges = 0;
  int badgeBaselineStreak = 0;
  Map<String, int> badgeBaselineProjectMinutes = {};

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
      if (daysSince >= 7 && DateTime(last.year, last.month, last.day) != DateTime(now.year, now.month, now.day)) {
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

    final weekPlan = plan.where((x) => !x.date.isBefore(start) && x.date.isBefore(end)).toList();
    final plannedMinutes = weekPlan.fold(0, (a, x) => a + (x.plannedDuration > 0 ? x.plannedDuration : x.duration));
    final plannedSessions = weekPlan.where((x) => (x.plannedDuration > 0 || x.duration > 0)).length;
    final completedPlannedSessions = weekPlan.where((x) => x.completed && x.sourceSessionId != null).length;
    final realizedPlannedMinutes = weekPlan.fold(0, (a, x) {
      final source = x.sourceSessionId == null ? null : sessions.where((s) => s.id == x.sourceSessionId).firstOrNull;
      return a + (source?.duration ?? 0);
    });

    return WeeklyBilan(
      weekStart: start,
      totalMinutes: totalMinutes,
      plannedMinutes: plannedMinutes,
      realizedPlannedMinutes: realizedPlannedMinutes,
      plannedSessions: plannedSessions,
      completedPlannedSessions: completedPlannedSessions,
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

  void openProgressDashboard() {
    Navigator.of(navKey.currentContext!).push(
      MaterialPageRoute(
        builder: (_) => ProgressDashboardScreen(
          projects: projects,
          sessions: sessions,
          weeklyHistory: weeklyHistory,
          onOpenProject: (p) => addOrEditProject(p),
          onStartRecommended: startPracticeTimer,
        ),
      ),
    );
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
    final progressMinutes = (totalMinutesAllTime - badgeBaselineMinutes).clamp(0, 1 << 30);
    final progressSessions = (totalSessions - badgeBaselineSessions).clamp(0, 1 << 30);
    final progressPieces = (completedPieces - badgeBaselinePieces).clamp(0, 1 << 30);
    final progressChallenges = (challengesWon - badgeBaselineChallenges).clamp(0, 1 << 30);
    final progressStreak = (bestStreakEver - badgeBaselineStreak).clamp(0, 1 << 30);
    var deepProgress = 0;
    for (final e in byProject.entries) {
      final base = badgeBaselineProjectMinutes[e.key] ?? 0;
      deepProgress = math.max(deepProgress, (e.value - base).clamp(0, 1 << 30));
    }

    return [
      AppBadge('streak3', '🔥', '3 jours d\'affilée', 'Pratiquer 3 jours de suite', progressStreak >= 3, progress: progressStreak, target: 3),
      AppBadge('streak7', '🔥', '7 jours d\'affilée', 'Une semaine complète sans interruption', progressStreak >= 7, progress: progressStreak, target: 7),
      AppBadge('streak14', '🔥', '14 jours d\'affilée', 'Deux semaines de suite', progressStreak >= 14, progress: progressStreak, target: 14),
      AppBadge('streak30', '🔥', '30 jours d\'affilée', 'Un mois complet sans interruption', progressStreak >= 30, progress: progressStreak, target: 30),
      AppBadge('hours5', '⏱️', '5 h de pratique', 'Cumuler 5 heures de pratique au total', progressMinutes >= 300, progress: progressMinutes, target: 300),
      AppBadge('hours20', '⏱️', '20 h de pratique', 'Cumuler 20 heures de pratique au total', progressMinutes >= 1200, progress: progressMinutes, target: 1200),
      AppBadge('hours50', '⏱️', '50 h de pratique', 'Cumuler 50 heures de pratique au total', progressMinutes >= 3000, progress: progressMinutes, target: 3000),
      AppBadge('hours100', '⏱️', '100 h de pratique', 'Cumuler 100 heures de pratique au total', progressMinutes >= 6000, progress: progressMinutes, target: 6000),
      AppBadge('piece1', '🎉', 'Premier morceau terminé', 'Amener un morceau à 100 %', progressPieces >= 1, progress: progressPieces, target: 1),
      AppBadge('piece5', '🏆', '5 morceaux terminés', 'Amener 5 morceaux à 100 %', progressPieces >= 5, progress: progressPieces, target: 5),
      AppBadge('deep10', '🎹', '10 h sur un seul morceau', 'Approfondir un morceau en profondeur', deepProgress >= 600, progress: deepProgress, target: 600),
      AppBadge('challenge1', '🎯', 'Premier défi relevé', 'Réussir un défi hebdomadaire', progressChallenges >= 1, progress: progressChallenges, target: 1),
      AppBadge('challenge5', '🎯', '5 défis relevés', 'Réussir 5 défis hebdomadaires', progressChallenges >= 5, progress: progressChallenges, target: 5),
      AppBadge('sessions10', '📈', '10 sessions loguées', 'Enregistrer 10 séances de pratique', progressSessions >= 10, progress: progressSessions, target: 10),
      AppBadge('sessions50', '📈', '50 sessions loguées', 'Enregistrer 50 séances de pratique', progressSessions >= 50, progress: progressSessions, target: 50),
    ];
  }

  Future<void> resetBadges() async {
    final context = navKey.currentContext!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Réinitialiser les badges ?'),
        content: const Text('Les séances, morceaux et défis seront conservés. Les badges recommenceront simplement à compter à partir de maintenant.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Réinitialiser')),
        ],
      ),
    );
    if (confirmed != true) return;

    final totalMinutes = sessions.fold(0, (a, s) => a + s.duration);
    final completedPieces = projects.where((p) => p.progress >= 1).length;
    final challengesWon = challenges.where((c) => c.celebrated).length;
    final byProject = <String, int>{};
    for (final s in sessions) {
      if (s.projectId == null) continue;
      byProject[s.projectId!] = (byProject[s.projectId!] ?? 0) + s.duration;
    }
    setState(() {
      badgeBaselineMinutes = totalMinutes;
      badgeBaselineSessions = sessions.length;
      badgeBaselinePieces = completedPieces;
      badgeBaselineChallenges = challengesWon;
      badgeBaselineStreak = bestStreakEver;
      badgeBaselineProjectMinutes = Map<String, int>.from(byProject);
      seenBadgeIds = [];
    });
    await _persist();
  }

  Future<void> resetPracticeBase() async {
    final context = navKey.currentContext!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Repartir sur une base propre ?'),
        content: const Text(
          'Les fiches morceaux et les méthodes seront conservées. '
          'L’historique des séances, le planning généré, les défis, les badges et la série seront remis à zéro. '
          'La progression et le tempo actuel des morceaux seront également réinitialisés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final now = DateTime.now();

    setState(() {
      // Conserver la fiche du morceau, mais remettre à zéro les données issues de la pratique.
      for (final project in projects) {
        project.progress = 0;
        project.reading = 0;
        project.handsTogether = 0;
        project.memory = 0;
        project.interpretation = 0;
        project.currentTempo = 0;
        project.statusIsManual = false;
        project.status = statusFromStages(
          reading: 0,
          handsTogether: 0,
          memory: 0,
          interpretation: 0,
        );
        project.celebratedComplete = false;
      }

      sessions = [];
      plan = [];
      challenges = [];
      bestStreakEver = 0;
      seenBadgeIds = [];
      badgeBaselineMinutes = 0;
      badgeBaselineSessions = 0;
      badgeBaselinePieces = 0;
      badgeBaselineChallenges = 0;
      badgeBaselineStreak = 0;
      badgeBaselineProjectMinutes = {};

      // Les défis seront régénérés à partir d'une base vierge.
      _ensureWeeklyChallenges();

      // Évite qu'une ancienne date de sauvegarde fasse croire que la nouvelle base
      // de test est déjà sauvegardée.
      lastBackupAt = null;

      // Petite graine temporelle utile aux composants qui exploitent "aujourd'hui".
      weeklyInstructions = weeklyInstructions;
      _backupReminderShown = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastPracticeResetAt', now.toIso8601String());
    await _persist();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Base de test réinitialisée. Les morceaux et méthodes sont conservés.'),
      ),
    );
  }

  void openBadgesScreen() {
    Navigator.of(navKey.currentContext!).push(MaterialPageRoute(builder: (_) => BadgesScreen(
      badges: badges,
      onReset: resetBadges,
    )));
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
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _clockNow = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCapacity = prefs.getString('dailyCapacity');
    if (rawCapacity != null) {
      dailyCapacity = (jsonDecode(rawCapacity) as List).map((e) => e as int).toList();
    }
    weeklyInstructions = prefs.getString('weeklyInstructions') ?? '';
    coachRestDayKeys = (jsonDecode(prefs.getString('coachRestDayKeys') ?? '[]') as List).map((e) => e.toString()).toSet();
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
    final rawLastBackup = prefs.getString('lastBackupAt');
    lastBackupAt = rawLastBackup == null ? null : DateTime.tryParse(rawLastBackup);
    bestStreakEver = prefs.getInt('bestStreakEver') ?? 0;
    seenBadgeIds = (jsonDecode(prefs.getString('seenBadgeIds') ?? '[]') as List).map((e) => e as String).toList();
    badgeBaselineMinutes = prefs.getInt('badgeBaselineMinutes') ?? 0;
    badgeBaselineSessions = prefs.getInt('badgeBaselineSessions') ?? 0;
    badgeBaselinePieces = prefs.getInt('badgeBaselinePieces') ?? 0;
    badgeBaselineChallenges = prefs.getInt('badgeBaselineChallenges') ?? 0;
    badgeBaselineStreak = prefs.getInt('badgeBaselineStreak') ?? 0;
    final rawBadgeBaselineProjects = prefs.getString('badgeBaselineProjectMinutes');
    badgeBaselineProjectMinutes = rawBadgeBaselineProjects == null
        ? <String, int>{}
        : Map<String, int>.from((jsonDecode(rawBadgeBaselineProjects) as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
    final rawProjects = prefs.getString('projects');
    if (rawProjects == null) {
      _seedDemoData();
      await _persist();
    } else {
      projects = (jsonDecode(rawProjects) as List).map((e) => Project.fromJson(e)).toList();
      sessions = (jsonDecode(prefs.getString('sessions') ?? '[]') as List).map((e) => Session.fromJson(e)).toList();
      plan = (jsonDecode(prefs.getString('plan') ?? '[]') as List).map((e) => PlanItem.fromJson(e)).toList();
      coachDecisionLog = (jsonDecode(prefs.getString('coachDecisionLog') ?? '[]') as List).map((e) => CoachDecision.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      routine =
          (jsonDecode(prefs.getString('routine') ?? '[]') as List).map((e) => RoutineItem.fromJson(e)).toList();
      challenges =
          (jsonDecode(prefs.getString('challenges') ?? '[]') as List).map((e) => Challenge.fromJson(e)).toList();
    }
    _syncMethodsFromUsage();
    _ensureWeeklyChallenges();
    if (mounted) {
      setState(() => loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRemindBackup());
    }
  }

  Future<void> _maybeRemindBackup() async {
    if (!mounted || _backupReminderShown || loading) return;
    final now = DateTime.now();
    final last = lastBackupAt;
    final shouldRemind = last == null || now.difference(last).inDays >= _backupReminderDays;
    if (!shouldRemind) return;
    _backupReminderShown = true;

    final daysText = last == null
        ? 'Aucune sauvegarde n’est encore enregistrée.'
        : 'Ta dernière sauvegarde date d’il y a ${now.difference(last).inDays} jour${now.difference(last).inDays > 1 ? 's' : ''}.';

    await showDialog<void>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.backup_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Sauvegarde recommandée')),
        ]),
        content: Text('$daysText\n\nPour éviter de perdre ton planning, tes morceaux et tes sessions, pense à exporter régulièrement tes données.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Plus tard'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(c);
              exportData();
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('Sauvegarder maintenant'),
          ),
        ],
      ),
    );
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
    await prefs.setString('coachRestDayKeys', jsonEncode(coachRestDayKeys.toList()));
    await prefs.setString('learningMethods', jsonEncode(learningMethods));
    await prefs.setString('methodDefinitions', jsonEncode(methodDefinitions.map((e) => e.toJson()).toList()));
    await prefs.setBool('darkMode', darkMode);
    if (lastBackupAt != null) await prefs.setString('lastBackupAt', lastBackupAt!.toIso8601String());
    await prefs.setInt('bestStreakEver', bestStreakEver);
    await prefs.setString('seenBadgeIds', jsonEncode(seenBadgeIds));
    await prefs.setInt('badgeBaselineMinutes', badgeBaselineMinutes);
    await prefs.setInt('badgeBaselineSessions', badgeBaselineSessions);
    await prefs.setInt('badgeBaselinePieces', badgeBaselinePieces);
    await prefs.setInt('badgeBaselineChallenges', badgeBaselineChallenges);
    await prefs.setInt('badgeBaselineStreak', badgeBaselineStreak);
    await prefs.setString('badgeBaselineProjectMinutes', jsonEncode(badgeBaselineProjectMinutes));
    await prefs.setString('projects', jsonEncode(projects.map((e) => e.toJson()).toList()));
    await prefs.setString('sessions', jsonEncode(sessions.map((e) => e.toJson()).toList()));
    await prefs.setString('plan', jsonEncode(plan.map((e) => e.toJson()).toList()));
    await prefs.setString('coachDecisionLog', jsonEncode(coachDecisionLog.map((e) => e.toJson()).toList()));
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

  String _dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';


  /// Telecharge un fichier .json contenant toutes les donnees de l'application (sauvegarde).
  void exportData() {
    final backupNow = DateTime.now();
    if (mounted) setState(() => lastBackupAt = backupNow);
    _persist();
    final data = {
      'dailyCapacity': dailyCapacity,
      'weeklyInstructions': weeklyInstructions,
      'coachRestDayKeys': coachRestDayKeys.toList(),
      'learningMethods': learningMethods,
      'methodDefinitions': methodDefinitions.map((e) => e.toJson()).toList(),
      'darkMode': darkMode,
      'bestStreakEver': bestStreakEver,
      'seenBadgeIds': seenBadgeIds,
      'badgeBaselineMinutes': badgeBaselineMinutes,
      'badgeBaselineSessions': badgeBaselineSessions,
      'badgeBaselinePieces': badgeBaselinePieces,
      'badgeBaselineChallenges': badgeBaselineChallenges,
      'badgeBaselineStreak': badgeBaselineStreak,
      'badgeBaselineProjectMinutes': badgeBaselineProjectMinutes,
      'projects': projects.map((e) => e.toJson()).toList(),
      'sessions': sessions.map((e) => e.toJson()).toList(),
      'plan': plan.map((e) => e.toJson()).toList(),
      'coachDecisionLog': coachDecisionLog.map((e) => e.toJson()).toList(),
      'routine': routine.map((e) => e.toJson()).toList(),
      'challenges': challenges.map((e) => e.toJson()).toList(),
      'exportedAt': backupNow.toIso8601String(),
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
        coachRestDayKeys = ((data['coachRestDayKeys'] as List?) ?? []).map((e) => e.toString()).toSet();
        if (data['learningMethods'] is List) {
          learningMethods = (data['learningMethods'] as List).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toSet().toList();
        }
        darkMode = data['darkMode'] as bool? ?? false;
        bestStreakEver = data['bestStreakEver'] as int? ?? 0;
        seenBadgeIds = ((data['seenBadgeIds'] as List?) ?? []).map((e) => e as String).toList();
        badgeBaselineMinutes = (data['badgeBaselineMinutes'] as num?)?.toInt() ?? 0;
        badgeBaselineSessions = (data['badgeBaselineSessions'] as num?)?.toInt() ?? 0;
        badgeBaselinePieces = (data['badgeBaselinePieces'] as num?)?.toInt() ?? 0;
        badgeBaselineChallenges = (data['badgeBaselineChallenges'] as num?)?.toInt() ?? 0;
        badgeBaselineStreak = (data['badgeBaselineStreak'] as num?)?.toInt() ?? 0;
        final importedBadgeProjects = data['badgeBaselineProjectMinutes'];
        badgeBaselineProjectMinutes = importedBadgeProjects is Map
            ? Map<String, int>.from(importedBadgeProjects.map((k, v) => MapEntry(k.toString(), (v as num).toInt())))
            : <String, int>{};
        projects = ((data['projects'] as List?) ?? []).map((e) => Project.fromJson(e)).toList();
        sessions = ((data['sessions'] as List?) ?? []).map((e) => Session.fromJson(e)).toList();
        plan = ((data['plan'] as List?) ?? []).map((e) => PlanItem.fromJson(e)).toList();
        coachDecisionLog = ((data['coachDecisionLog'] as List?) ?? []).map((e) => CoachDecision.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        routine = ((data['routine'] as List?) ?? []).map((e) => RoutineItem.fromJson(e)).toList();
        challenges = ((data['challenges'] as List?) ?? []).map((e) => Challenge.fromJson(e)).toList();
        final importedBackup = data['exportedAt']?.toString();
        lastBackupAt = importedBackup == null ? null : DateTime.tryParse(importedBackup);
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
      reviewBudget = desired < normalCap ? desired : normalCap;

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
        final focusBonus = p.workIntensity == 'Forte' ? 1.18 : (p.workIntensity == 'Faible' ? .90 : 1.0);
        weightById[p.id] = (1 - p.progress) * (p.priority ? 1.75 : 1) * recencyBonus * stageBonus * focusBonus * m;
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
      map[cat] = (map[cat] ?? 0) + x.plannedDuration;
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

  String _methodPlanningDetails(Project project) {
    final parts = <String>[];
    if (project.measures.trim().isNotEmpty) parts.add('Mesures ${project.measures.trim()}');
    final focus = project.effectiveWorkFocus;
    if (focus.isNotEmpty) parts.add('${workFocusEmoji(focus)} $focus');
    if (project.workIntensity != 'Moyenne' && project.workFocus != 'Automatique') parts.add('intensité ${project.workIntensity.toLowerCase()}');
    if (project.currentTempo > 0 && project.targetTempo > 0 && project.currentTempo < project.targetTempo && (focus == 'Tempo' || focus == 'Automatique')) {
      parts.add('${project.currentTempo} → ${project.targetTempo} BPM');
    }
    if (project.method != null && project.method!.trim().isNotEmpty) parts.add(project.method!.trim());
    return parts.isEmpty ? 'Travail ciblé du morceau' : parts.join(' · ');
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
    return showDialog<MethodDefinition>(context: context, builder: (c) => StatefulBuilder(builder: (c, setD) {
      final flatTheme = Theme.of(c).copyWith(
        inputDecorationTheme: Theme.of(c).inputDecorationTheme.copyWith(
          border: const UnderlineInputBorder(),
          enabledBorder: const UnderlineInputBorder(),
          focusedBorder: const UnderlineInputBorder(),
          errorBorder: const UnderlineInputBorder(),
          focusedErrorBorder: const UnderlineInputBorder(),
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.only(left: 0, right: 0, top: 10, bottom: 8),
        ),
      );
      return Theme(data: flatTheme, child: AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
      contentPadding: const EdgeInsets.fromLTRB(22, 6, 22, 6),
      actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      title: Text(initial == null ? 'Nouvelle méthode' : 'Modifier la méthode'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _detailSectionHeader(c, 'IDENTITÉ', icon: Icons.menu_book_outlined),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom de la méthode*')),
        const SizedBox(height: 6),
        TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 6),
        _detailSectionHeader(c, 'CONTENU', icon: Icons.school_outlined),
        TextField(controller: objectives, maxLines: 3, decoration: const InputDecoration(labelText: 'Objectifs')),
        const SizedBox(height: 6),
        TextField(controller: exercises, maxLines: 4, decoration: const InputDecoration(labelText: 'Exercices / déroulé')),
        const SizedBox(height: 6),
        TextField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Durée recommandée (minutes)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: level, decoration: const InputDecoration(labelText: 'Niveau'), items: const [
          DropdownMenuItem(value: 'Tous niveaux', child: Text('Tous niveaux')), DropdownMenuItem(value: 'Débutant', child: Text('Débutant')), DropdownMenuItem(value: 'Intermédiaire', child: Text('Intermédiaire')), DropdownMenuItem(value: 'Avancé', child: Text('Avancé')), DropdownMenuItem(value: 'Débutant à intermédiaire', child: Text('Débutant à intermédiaire')), DropdownMenuItem(value: 'Intermédiaire à avancé', child: Text('Intermédiaire à avancé')),
        ], onChanged: (v) => setD(() => level = v ?? level)),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')), FilledButton(onPressed: () { final mins = (int.tryParse(duration.text.trim()) ?? 20).clamp(1, 180); Navigator.pop(c, MethodDefinition(name: name.text.trim(), description: description.text.trim(), objectives: objectives.text.trim(), exercises: exercises.text.trim(), durationMinutes: mins, level: level)); }, child: const Text('Enregistrer'))],
      ));
    }));
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
                  'Les seances non terminees des 7 prochains jours seront remplacees. Ta routine reserve son temps en premier chaque jour concerne, puis le reste est reparti entre tes morceaux selon leur avancement, leur besoin réel et une rotation quotidienne pour favoriser la variété. Ensuite, le coach pourra recalibrer les jours suivants selon le temps réellement joué et le ressenti.',
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
      coachRestDayKeys.clear();

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

      // --- Passe 2 : répartition quotidienne intelligente des morceaux (V72). ---
      // V20 : le type de travail du morceau influence désormais la durée naturelle du bloc.
      // Les accords, le rythme ou un passage difficile restent volontairement courts,
      // tandis que le déchiffrage ou l'interprétation peuvent prendre plus de temps.
      // La priorité reste indépendante du besoin de travail.
      // L'objectif est d'obtenir des journées naturelles plutôt que 80/10/10.
      if (rec.isNotEmpty) {
        final remainingByProject = <String, int>{
          for (final e in rec.entries.where((e) => e.value > 0)) e.key: e.value,
        };
        final itemByDayAndProject = <String, PlanItem>{};
        final lastProjectByDay = <DateTime, String>{};
        // V72 : mémoire de rotation sur les jours déjà construits. Elle permet
        // d'éviter de remettre le même morceau trop souvent, sans bloquer un
        // morceau réellement prioritaire ou en difficulté.
        final scheduledProjectsByDay = <DateTime, Set<String>>{};
        final scheduledFocusByDay = <DateTime, Set<String>>{};
        final lastScheduledDayByProject = <String, DateTime>{};
        final scheduledCountByProject = <String, int>{};
        final scheduledMinutesByFocus = <String, int>{};
        const minUsefulMinutes = 10;
        const maxDailyMinutes = 40;

        DateTime? latestSessionFor(String projectId) {
          DateTime? latest;
          for (final s in sessions.where((s) => s.projectId == projectId)) {
            if (latest == null || s.date.isAfter(latest!)) latest = s.date;
          }
          return latest;
        }

        List<Session> runThroughHistory(String projectId) {
          final list = sessions
              .where((s) => s.projectId == projectId && s.type == 'Run-through' && s.runThroughCompleted == true)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          return list;
        }

        bool runThroughDue(Project p, DateTime day) {
          if (p.targetTempo <= 0) return false;
          if (p.progress < .65 && p.effectiveStatus != 'Acquis' && p.effectiveStatus != 'Répertoire d’entretien') {
            return false;
          }
          final history = runThroughHistory(p.id);
          if (history.isEmpty) {
            return p.progress >= .75 || p.effectiveStatus == 'Acquis' || p.effectiveStatus == 'Répertoire d’entretien';
          }
          final lastRun = history.first.date;
          final daysSince = day.difference(DateTime(lastRun.year, lastRun.month, lastRun.day)).inDays;
          if (daysSince < 7) return false;
          final endTempo = history.first.runThroughEndTempo ?? 0;
          final tempoRatio = endTempo > 0 ? endTempo / p.targetTempo : 0.0;
          return tempoRatio >= .80 || p.effectiveStatus == 'Répertoire d’entretien' || p.progress >= .85;
        }

        String planningFocus(Project p) {
          final focus = p.effectiveWorkFocus;
          return focus.isEmpty ? 'Consolidation' : focus;
        }

        int recentPlannedContacts(String projectId, DateTime day, int windowDays) {
          var count = 0;
          for (var i = 1; i <= windowDays; i++) {
            final d = DateTime(day.year, day.month, day.day).subtract(Duration(days: i));
            if (scheduledProjectsByDay[d]?.contains(projectId) == true) count++;
          }
          return count;
        }

        int recentPlannedDistinctProjects(DateTime day, int windowDays) {
          final ids = <String>{};
          for (var i = 1; i <= windowDays; i++) {
            final d = DateTime(day.year, day.month, day.day).subtract(Duration(days: i));
            ids.addAll(scheduledProjectsByDay[d] ?? const <String>{});
          }
          return ids.length;
        }

        bool focusUsedYesterday(DateTime day, String focus) {
          final d = DateTime(day.year, day.month, day.day).subtract(const Duration(days: 1));
          return scheduledFocusByDay[d]?.contains(focus) == true;
        }

        double actualAdherence(String projectId) {
          final recent = sessions
              .where((s) => s.projectId == projectId && s.plannedDuration != null && s.plannedDuration! > 0)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          final selected = recent.take(4).toList();
          if (selected.isEmpty) return 1.0;
          return selected.fold<double>(0, (sum, s) => sum + (s.duration / s.plannedDuration!)) / selected.length;
        }

        double actualLoadAdjustment(String projectId) {
          final a = actualAdherence(projectId);
          final p = projectById(projectId);
          if (p == null) return 1.0;
          final difficultRecent = _recentDifficultSessions(projectId);
          if (difficultRecent >= 2) return .88;
          if (a < .78) return .88;
          if (a < .90) return .95;
          if (a > 1.18 && _lastFeeling(projectId) != 'difficile') return 1.08;
          if (a > 1.05 && _lastFeeling(projectId) == 'facile') return 1.04;
          return 1.0;
        }

        double projectNeed(String projectId, DateTime day) {
          final p = projectById(projectId);
          if (p == null) return 0;

          final last = latestSessionFor(projectId);
          final daysSince = last == null
              ? 999
              : day.difference(DateTime(last.year, last.month, last.day)).inDays;
          final recency = daysSince >= 14
              ? 1.55
              : (daysSince >= 7 ? 1.28 : (daysSince >= 3 ? 1.08 : .92));

          final stage = 1.0 + (1.0 - p.weakestStageValue) * .30;
          final priority = p.priority ? 1.35 : 1.0;
          final difficult = _recentDifficultSessions(p.id) >= 2 ? 1.16 : 1.0;

          // On espace les contacts : un morceau vu hier reste éligible, mais
          // il doit être nettement plus prioritaire pour être reprogrammé.
          final lastScheduled = lastScheduledDayByProject[p.id];
          final spacingPenalty = lastScheduled == null
              ? 1.0
              : (day.difference(lastScheduled).inDays <= 1 ? .58 : 1.0);

          // Un Run-through terminé devient une vraie étape du parcours :
          // lorsqu'il est arrivé à échéance, on donne un bonus pour le placer
          // plutôt que de refaire automatiquement le même type de travail.
          final runBonus = runThroughDue(p, day) ? 1.34 : 1.0;

          final learnedLoad = actualLoadAdjustment(projectId);
          return (1.0 + (1.0 - p.progress) * .85) *
              recency *
              stage *
              priority *
              difficult *
              spacingPenalty *
              learnedLoad *
              runBonus;
        }

        // On remplit chaque journée par des séances naturelles : au maximum
        // un bloc par morceau et par jour. Le moteur préfère laisser quelques
        // minutes libres plutôt que fabriquer des reliquats de 5–10 min.
        for (final day in days) {
          var guard = 0;
          while ((remainingByDay[day] ?? 0) >= minUsefulMinutes &&
              remainingByProject.isNotEmpty &&
              guard++ < 50) {
            final dayRemaining = remainingByDay[day]!;
            final candidates = remainingByProject.keys
                .where((id) => remainingByProject[id]! > 0)
                .toList();
            if (candidates.isEmpty) break;

            // Un même morceau n'est planifié qu'une seule fois par jour.
            // Cela évite les enchaînements 10 + 10 + 10 min sur la même pièce.
            final untouched = candidates
                .where((id) =>
                    !itemByDayAndProject.containsKey('${day.toIso8601String()}|$id'))
                .toList();

            // Si tous les morceaux ont déjà eu leur bloc aujourd'hui, on préfère
            // garder le temps restant libre plutôt que de fractionner davantage.
            if (untouched.isEmpty) break;

            // Choix par score : besoin + poids hebdomadaire restant + rotation.
            String bestId = untouched.first;
            var bestScore = -1.0;
            final totalRemaining = candidates
                .map((x) => remainingByProject[x]!.toDouble())
                .fold(0.0, (a, b) => a + b);

            for (final id in untouched) {
              final remaining = remainingByProject[id]!.toDouble();
              final weeklyShare =
                  totalRemaining > 0 ? remaining / totalRemaining : 0.0;
              final alternation = lastProjectByDay[day] == id ? 0.55 : 1.0;
              final need = projectNeed(id, day);

              // V72 — rotation quotidienne : un morceau travaillé hier reste
              // possible, mais il doit apporter un besoin nettement supérieur
              // pour reprendre immédiatement sa place. On regarde aussi les
              // 3 derniers jours pour favoriser une vraie variété des morceaux.
              final contacts3d = recentPlannedContacts(id, day, 3);
              final rotationPenalty = contacts3d >= 2
                  ? .42
                  : (contacts3d == 1 ? .68 : 1.0);

              // Bonus léger aux morceaux absents des derniers jours : cela évite
              // qu'une seule pièce monopolise le planning même si elle est prioritaire.
              final recentDistinct = recentPlannedDistinctProjects(day, 3);
              final diversityBonus = contacts3d == 0 && recentDistinct >= 2 ? 1.08 : 1.0;

              // Le moteur équilibre aussi les types de travail sur la semaine :
              // si un focus a déjà pris beaucoup de place, son score baisse un peu.
              final p = projectById(id);
              final focus = p == null ? 'Consolidation' : planningFocus(p);
              final focusMinutes = scheduledMinutesByFocus[focus] ?? 0;
              final focusPenalty = focusMinutes >= 60 ? .76 : (focusMinutes >= 45 ? .88 : 1.0);

              // Evite de monopoliser la semaine avec un seul morceau.
              final scheduledCount = scheduledCountByProject[id] ?? 0;
              final contactPenalty = scheduledCount >= 4
                  ? .52
                  : (scheduledCount >= 3 ? .78 : (scheduledCount >= 2 ? .92 : 1.0));

              final focusRotation = focusUsedYesterday(day, focus) ? .78 : 1.0;

              final score =
                  (weeklyShare * .58 + need * .42) *
                  alternation *
                  rotationPenalty *
                  diversityBonus *
                  focusRotation *
                  focusPenalty *
                  contactPenalty;
              if (score > bestScore) {
                bestScore = score;
                bestId = id;
              }
            }

            final project = projectById(bestId);
            if (project == null) {
              remainingByProject.remove(bestId);
              continue;
            }

            final dueForRunThrough = runThroughDue(project, day);
            final focus = dueForRunThrough ? 'Interprétation' : project.effectiveWorkFocus;
            final focusMax = workFocusMaxMinutes(focus);
            final focusMin = workFocusMinMinutes(focus);

            // Durée cible naturelle pour une vraie séance. Les travaux courts
            // restent courts (20 min max), tandis que déchiffrage/mains ensemble
            // peuvent prendre 30 min. On ne cherche plus à remplir artificiellement
            // la journée minute par minute.
            int naturalTarget;
            switch (focus) {
              case 'Accords':
              case 'Rythme':
              case 'Passages difficiles':
              case 'Entretien':
                naturalTarget = 20;
                break;
              case 'Tempo':
              case 'Mémorisation':
              case 'Consolidation':
                naturalTarget = 25;
                break;
              default:
                naturalTarget = 30;
                break;
            }

            var chunk = math.min(
              remainingByProject[bestId]!,
              math.min(dayRemaining, math.min(focusMax, naturalTarget)),
            );

            // Si le reliquat du morceau est petit, on le termine en un seul bloc.
            if (remainingByProject[bestId]! <= naturalTarget) {
              chunk = math.min(
                remainingByProject[bestId]!,
                math.min(dayRemaining, focusMax),
              );
            }

            // V120 : le planning apprend du temps réellement joué. On ne propose
            // pas 30 min à quelqu'un qui n'en réalise régulièrement que 20, et inversement
            // on autorise un léger allongement lorsque les séances sont réellement tenues.
            final adherence = actualAdherence(bestId);
            if (adherence < .82) {
              chunk = math.min(chunk, math.max(focusMin, naturalTarget - 5));
            } else if (adherence > 1.15 && _lastFeeling(bestId) != 'difficile') {
              chunk = math.min(chunk, math.min(focusMax, naturalTarget + 5));
            }

            // Si la journée n'offre que son dernier petit reliquat, on ne crée pas
            // un bloc artificiel : on arrête la génération et la minute restante
            // demeure disponible pour une pratique libre.
            if (chunk < focusMin) break;

            final key = '${day.toIso8601String()}|$bestId';
            final baseDetails = _methodPlanningDetails(project);
            final detailsPrefix = baseDetails.isEmpty ? '' : '$baseDetails · ';
            final planningDetails = dueForRunThrough
                ? '${detailsPrefix}Run-through · exécution complète${project.targetTempo > 0 ? ' · cible ${project.targetTempo} BPM' : ''}'
                : baseDetails;

            final adaptiveAdherence = actualAdherence(bestId);
            final adaptiveTag = adaptiveAdherence == 1.0 ? '' : ' · adaptation ${ (adaptiveAdherence * 100).round()} % du temps habituel';

            final item = PlanItem(
              id: newId(),
              date: day,
              duration: chunk,
              title: project.name,
              details: '$planningDetails$adaptiveTag',
              projectId: project.id,
              category: dueForRunThrough ? 'Run-through' : project.weakestCategory,
              method: project.method,
            );
            itemByDayAndProject[key] = item;
            plan.add(item);

            remainingByProject[bestId] =
                remainingByProject[bestId]! - chunk;
            remainingByDay[day] =
                remainingByDay[day]! - chunk;
            lastProjectByDay[day] = bestId;
            scheduledProjectsByDay.putIfAbsent(day, () => <String>{}).add(bestId);
            scheduledFocusByDay.putIfAbsent(day, () => <String>{}).add(focus);
            lastScheduledDayByProject[bestId] = day;
            scheduledCountByProject[bestId] =
                (scheduledCountByProject[bestId] ?? 0) + 1;
            scheduledMinutesByFocus[focus] =
                (scheduledMinutesByFocus[focus] ?? 0) + chunk;

            if (remainingByProject[bestId]! <= 0) {
              remainingByProject.remove(bestId);
            }
          }
        }
      }

      // Tout jour laissé volontairement vide par cette génération est marqué comme
      // repos du coach. On ne marque pas comme repos les journées déclarées
      // indisponibles (capacité = 0).
      for (final d in days) {
        final hasItem = plan.any((x) => !x.completed && _sameDay(x.date, d));
        if (!hasItem && dailyCapacity[d.weekday - 1] > 0) {
          coachRestDayKeys.add(_dayKey(d));
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
      if (existing == null) _syncCompletedPlanItemsForSession(r);
      _auditPlanningIntegrity();
      _auditSessionIntegrity();
    });
    await _persist();

    // Une session AJOUTEE manuellement est une vraie fin de session, au même
    // titre qu'une session issue du chrono ou du planning : on propose donc
    // systématiquement la mise à jour des 4 étapes du morceau.
    // Une modification d'une session existante ne déclenche pas cette invite.
    if (existing == null && r.projectId != null) {
      await _offerDetailedProgress(r);
      await _waitForDialogTransition();
      await _showCoachFeedback(r);
    }
    // Le ressenti est maintenant enregistré : le coach peut réellement
    // recalibrer les jours futurs après cette séance.
      final coachChanged = _adaptRemainingWeekToReality();
      setState(() {});
      await _persist();
      _recordCoachDecision(r, coachChanged);
      await _persist();
      await _showCoachPlanningResult(r, coachChanged);
    await _showPlanVsRealized(r);
    _checkCelebrations();
  }

  String _coachPlanDateLabel(DateTime value) {
    const weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    final local = value.toLocal();
    return '${weekdays[local.weekday - 1]} ${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String _coachDecisionTargetLabel(CoachDecision d) {
    final target = d.adjustedPlanDate;
    if (target == null) return 'Date de l’ajustement : non disponible dans cet ancien journal';
    return 'Séance ajustée : ${_coachPlanDateLabel(target)}';
  }

  void _recordCoachDecision(Session session, bool changed) {
    final existing = coachDecisionLog.where((d) => d.sessionId == session.id).toList();
    if (existing.isNotEmpty) return;
    final projectId = session.projectId;
    final analyzedProject = projectById(projectId);
    final item = _lastCoachChangedItemId == null
        ? null
        : plan.where((x) => x.id == _lastCoachChangedItemId).firstOrNull;
    final adjustedProject = item == null ? null : projectById(item.projectId);
    final adjustedDate = item?.date;
    final decision = CoachDecision(
      id: newId(),
      date: DateTime.now(),
      sessionId: session.id,
      projectId: projectId,
      changed: changed,
      title: changed ? 'Planning ajusté' : 'Analyse du coach',
      message: changed
          ? 'Le coach a modifié le planning pour ${adjustedProject?.name ?? item?.title ?? 'cette séance'} le ${adjustedDate == null ? 'jour concerné' : _coachPlanDateLabel(adjustedDate)}.'
              '${item?.title != null && item!.title.trim().isNotEmpty && item.title != adjustedProject?.name ? ' ${item.title}.' : ''}'
          : 'J’ai analysé ta séance sur ${analyzedProject?.name ?? 'ce morceau'}. Rien ne justifie de changer le planning.',
      oldDuration: changed ? _lastCoachOldDuration : null,
      newDuration: changed ? _lastCoachNewDuration : null,
      reason: changed ? _lastCoachReason : null,
      adjustedPlanItemId: changed ? item?.id : null,
      adjustedProjectId: changed ? item?.projectId : null,
      adjustedPlanDate: changed ? adjustedDate : null,
    );
    coachDecisionLog.insert(0, decision);
    if (coachDecisionLog.length > 50) {
      coachDecisionLog.removeRange(50, coachDecisionLog.length);
    }
  }

  Future<void> _showCoachDecisionLog() async {
    final decisions = [...coachDecisionLog]..sort((a, b) => b.date.compareTo(a.date));
    await showDialog<void>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        title: const Text('🧠 Journal du coach'),
        content: SizedBox(
          width: 520,
          height: 430,
          child: decisions.isEmpty
              ? const Center(child: Text('Aucune décision du coach enregistrée.'))
              : ListView.separated(
                  itemCount: decisions.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final d = decisions[i];
                    final date = '${d.date.day.toString().padLeft(2,'0')}/${d.date.month.toString().padLeft(2,'0')} · ${d.date.hour.toString().padLeft(2,'0')}:${d.date.minute.toString().padLeft(2,'0')}';
                    final analyzedProjectName = projectById(d.projectId)?.name;
                    final adjustedProjectName = projectById(d.adjustedProjectId)?.name;
                    final target = d.changed
                        ? '${adjustedProjectName ?? 'Morceau du planning'} · ${_coachDecisionTargetLabel(d)}'
                        : (analyzedProjectName == null ? '' : 'Séance analysée : $analyzedProjectName');
                    final details = [
                      date,
                      if (target.isNotEmpty) target,
                      d.message,
                      if ((d.reason ?? '').trim().isNotEmpty) d.reason!,
                    ].join('\n');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 17,
                        child: Icon(d.changed ? Icons.auto_awesome : Icons.check, size: 17),
                      ),
                      title: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(details, maxLines: 6, overflow: TextOverflow.ellipsis),
                      trailing: d.oldDuration != null && d.newDuration != null
                          ? Text('${d.oldDuration} → ${d.newDuration} min', style: const TextStyle(fontWeight: FontWeight.w800))
                          : null,
                    );
                  },
                ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))],
      ),
    );
  }

  /// V121 : le planning constitue la stratégie de la semaine, mais les jours
  /// encore à venir sont recalibrés à partir de la pratique réellement observée.
  /// Les séances terminées ne sont jamais modifiées ; seules les séances futures
  /// non commencées peuvent voir leur durée ajustée.
  Future<void> _showCoachPlanningResult(Session session, bool changed) async {
    final project = projectById(session.projectId);
    final name = project?.name ?? 'ta séance';
    final title = changed ? '🧠 Planning ajusté' : '🧠 Analyse du coach';
    final message = changed
        ? 'J’ai analysé ta séance et ajusté le planning à venir.'
        : 'J’ai analysé ta séance. Rien ne justifie de changer le planning.';
    await showDialog<void>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(height: 1.4)),
            if (changed) ...[
              const SizedBox(height: 10),
              const Text('Un indicateur COACH apparaît sur le planning modifié.',
                  style: TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _adaptRemainingWeekToReality() {
    _lastCoachChangedItemId = null;
    _lastCoachOldDuration = null;
    _lastCoachNewDuration = null;
    _lastCoachReason = null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = startOfWeek(now);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final future = plan.where((x) =>
        !x.completed &&
        x.date.isAfter(today) &&
        !x.date.isBefore(weekStart) &&
        x.date.isBefore(weekEnd) &&
        x.duration > 0 &&
        x.sourceSessionId == null).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (future.isEmpty) return false;

    final orderedSessions = [...sessions]..sort((a, b) => b.date.compareTo(a.date));
    final latestSession = orderedSessions.isEmpty ? null : orderedSessions.first;
    bool changed = false;

    double factorForProject(String? projectId) {
      if (projectId == null || projectId.isEmpty) return 1.0;
      final recent = sessions
          .where((s) => s.projectId == projectId && s.plannedDuration != null && s.plannedDuration! > 0)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (recent.isEmpty) return 1.0;
      final selected = recent.take(4).toList();
      final adherence = selected.fold<double>(
            0,
            (sum, s) => sum + s.duration / s.plannedDuration!,
          ) /
          selected.length;
      final last = selected.first;
      if (last.coachFeeling == 'difficile' || _recentDifficultSessions(projectId) >= 2) return .88;
      if (last.duration <= last.plannedDuration! - 5 || adherence < .78) return .90;
      if (last.coachFeeling == 'facile' && last.duration >= last.plannedDuration!) return 1.08;
      if (last.duration >= last.plannedDuration! + 5 || adherence > 1.18) return 1.06;
      return 1.0;
    }

    bool applyAdjustment(PlanItem item, double factor, String reason) {
      final adjusted = (item.duration * factor).round().clamp(10, 30).toInt();
      if (adjusted == item.duration) return false;

      // Anti-oscillation : sur une même occurrence, le coach ne renverse pas
      // immédiatement sa dernière décision. Il attend au moins 48 h et une
      // nouvelle information réellement exploitable.
      final lastAt = item.coachAdjustedAt;
      final previous = item.coachPreviousDuration;
      if (lastAt != null && previous != null) {
        final age = DateTime.now().difference(lastAt);
        final lastDirection = item.duration - previous;
        final newDirection = adjusted - item.duration;
        if (age < const Duration(hours: 48) && lastDirection * newDirection < 0) {
          return false;
        }
      }

      final oldDuration = item.duration;
      item.duration = adjusted;
      item.coachAdjusted = true;
      item.coachAdjustmentSeen = false;
      item.coachAdjustmentReason = reason;
      item.coachAdjustedAt = DateTime.now();
      item.coachPreviousDuration = oldDuration;
      _lastCoachChangedItemId = item.id;
      _lastCoachOldDuration = oldDuration;
      _lastCoachNewDuration = adjusted;
      _lastCoachReason = reason;
      return true;
    }

    if (latestSession?.projectId != null) {
      final projectId = latestSession!.projectId!;
      final sameProject = future.where((x) => x.projectId == projectId).toList();
      final factor = factorForProject(projectId);
      if (factor != 1.0 && sameProject.isNotEmpty) {
        final item = sameProject.first;
        final reason = factor < 1
            ? 'Après la dernière séance, le coach réduit la prochaine charge.'
            : 'Après la dernière séance, le coach augmente légèrement la prochaine charge.';
        changed = applyAdjustment(item, factor, reason);
      }
    }

    if (!changed) {
      for (final item in future) {
        if (item.projectId == null) continue;
        final factor = factorForProject(item.projectId);
        if (factor == 1.0) continue;
        final reason = factor < 1
            ? 'Le coach allège cette séance à partir des dernières données.'
            : 'Le coach augmente légèrement cette séance à partir des dernières données.';
        if (applyAdjustment(item, factor, reason)) {
          changed = true;
          break;
        }
      }
    }

    if (!changed && latestSession?.projectId != null && latestSession?.coachFeeling == 'difficile') {
      final projectId = latestSession!.projectId!;
      final matching = future.where((x) => x.projectId == projectId).toList();
      final item = matching.isNotEmpty ? matching.first : future.first;
      final adjusted = math.max(10, item.duration - 5);
      if (adjusted != item.duration) {
        final previous = item.coachPreviousDuration;
        final lastAt = item.coachAdjustedAt;
        final reversing = previous != null && (item.duration - previous) * (adjusted - item.duration) < 0;
        final recent = lastAt != null && DateTime.now().difference(lastAt) < const Duration(hours: 48);
        if (!(reversing && recent)) {
          final oldDuration = item.duration;
          item.duration = adjusted;
          item.coachAdjusted = true;
          item.coachAdjustmentSeen = false;
          item.coachAdjustmentReason = 'Le coach allège de 5 min après une séance ressentie comme difficile.';
          item.coachAdjustedAt = DateTime.now();
          item.coachPreviousDuration = oldDuration;
          _lastCoachChangedItemId = item.id;
          _lastCoachOldDuration = oldDuration;
          _lastCoachNewDuration = adjusted;
          _lastCoachReason = item.coachAdjustmentReason;
          changed = true;
        }
      }
    }

    return changed;
  }

  Future<void> _showPlanVsRealized(Session s) async {
    if (s.plannedDuration == null && s.plannedTempo == null) return;
    final p = projectById(s.projectId);
    final planned = s.plannedDuration;
    final actual = s.duration;
    final durationText = planned == null
        ? null
        : '${actual} min ${actual == planned ? '· conforme au plan' : actual > planned ? '· +${actual - planned} min' : '· ${actual - planned} min'}';
    final tempoText = s.plannedTempo != null && p != null && p.currentTempo > 0
        ? '${s.plannedTempo} BPM → ${p.currentTempo} BPM'
        : null;
    if (durationText == null && tempoText == null) return;
    if (!mounted) return;
    await showDialog<void>(
      context: navKey.currentContext!,
      builder: (c) => AlertDialog(
        title: const Text('📊 Prévu / réalisé'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (planned != null) ...[
            const Text('⏱️ Durée', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text('Prévu : $planned min\nRéalisé : $actual min'),
          ],
          if (tempoText != null) ...[
            const SizedBox(height: 10),
            const Text('🎹 Tempo', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(tempoText),
          ],
          const SizedBox(height: 10),
          Text(s.coachFocus == null ? 'Le coach ajustera la prochaine séance selon le ressenti et les progrès.' : '🎯 Focus : ${s.coachFocus}', style: const TextStyle(height: 1.35)),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
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

  Future<void> startRunThrough(Project project, {PlanItem? plannedItem}) async {
    final elapsedMinutes = await Navigator.of(navKey.currentContext!).push<int>(
      MaterialPageRoute(
        builder: (_) => const PracticeTimerScreen(
          title: 'Run-through',
          subtitle: 'Joue le morceau du début à la fin sans t’arrêter pour corriger. Le but est de mesurer ce que tu arrives réellement à jouer en continu.',
        ),
      ),
    );
    if (elapsedMinutes == null) return;

    final result = await showDialog<_RunThroughResult>(
      context: navKey.currentContext!,
      builder: (_) => _RunThroughResultDialog(initialTempo: project.currentTempo > 0 ? project.currentTempo : null),
    );
    if (result == null) return;

    final stopNote = result.stopNote.trim();
    final noteText = stopNote.isEmpty
        ? (result.completed ? 'Exécution complète du morceau du début à la fin.' : 'Exécution interrompue.')
        : 'Exécution ${result.completed ? 'complète' : 'interrompue'} · $stopNote';

    final r = await showDialog<Session>(
      context: navKey.currentContext!,
      builder: (_) => SessionDialog(
        projects: projects,
        initialDuration: elapsedMinutes,
        initialProjectId: project.id,
        initialType: 'Run-through',
        initialNotes: noteText,
        initialMethod: project.method,
        initialCoachFocus: 'Exécution complète',
        initialCoachRecommendation: result.completed
            ? 'Run-through terminé : mesure surtout la continuité et la stabilité générale.'
            : 'Run-through interrompu : transforme le point d’arrêt en cible de travail pour la prochaine séance.',
        initialCoachTempo: project.currentTempo > 0 ? project.currentTempo : null,
        initialRunThroughCompleted: result.completed,
        initialRunThroughStopNote: stopNote.isEmpty ? null : stopNote,
        initialRunThroughStartTempo: result.startTempo,
        initialRunThroughEndTempo: result.endTempo,
        initialPlannedDuration: plannedItem?.duration,
      ),
    );
    if (r == null) return;

    setState(() {
      _capturePreviousProgress(r);
      sessions.insert(0, r);
      if (plannedItem != null) {
        plannedItem.completed = true;
        plannedItem.sourceSessionId = r.id;
      }
      _updateAutoProgress(r.projectId);
      _touchProject(r.projectId);
    });
    await _persist();
    await _offerDetailedProgress(r);
    await _waitForDialogTransition();
    await _showCoachFeedback(r);
    // Le bilan express vient d'enregistrer le ressenti : recalibrage après coup.
    final coachChanged = _adaptRemainingWeekToReality();
    setState(() {});
    await _persist();
    await _showCoachPlanningResult(r, coachChanged);
    await _showPlanVsRealized(r);
    _checkCelebrations();
  }

  /// Ouvre un chrono/minuteur pour la seance en cours. Si aucune entree n'est precisee,
  int? _tempoFromPlanDetails(String details) {
    final match = RegExp(r'(?:tempo\s*(?:de\s*référence|reference)?\s*[:→-]?\s*)?(\d+)\s*BPM', caseSensitive: false).firstMatch(details);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// propose d'abord de choisir parmi les seances planifiees du jour (ou "Nouvelle session
  /// libre"). A l'arret, ouvre le formulaire de session pre-rempli avec la duree ecoulee ;
  /// si une seance planifiee etait ciblee, elle est marquee terminee avec cette duree, sinon
  /// une nouvelle entree est ajoutee au planning du jour pour que tout reste coherent.
  Future<void> startPracticeTimer([PlanItem? target]) async {
    // Une séance déjà réalisée ne peut plus être relancée depuis le planning.
    // La protection est appliquée ici aussi pour éviter toute activation indirecte.
    if (target != null && target.completed) {
      if (navKey.currentContext != null) {
        ScaffoldMessenger.of(navKey.currentContext!).showSnackBar(
          const SnackBar(content: Text('Cette séance a déjà été réalisée.')),
        );
      }
      return;
    }
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

    if (chosen != null &&
        chosen.category == 'Run-through' &&
        chosen.projectId != null) {
      final project = projectById(chosen.projectId);
      if (project != null) {
        await startRunThrough(project, plannedItem: chosen);
        return;
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
          initialCoachFocus: planItem.motsCles.where((t) => t != 'Coach' && t != 'Prochaine séance').firstOrNull,
          initialCoachRecommendation: planItem.motsCles.contains('Coach') ? planItem.details : null,
          initialCoachTempo: _tempoFromPlanDetails(planItem.details) ?? (planItem.projectId == null ? null : projectById(planItem.projectId)?.currentTempo),
          initialPlannedDuration: planItem.duration,
        ),
      );
      if (r == null) return;
      setState(() {
        _capturePreviousProgress(r);
        sessions.insert(0, r);
        planItem.completed = true;
        planItem.sourceSessionId = r.id;
        // Une séance réalisée invalide toute autre recommandation coach concurrente du même jour.
        _removeDuplicatePendingCoachPlans(r.projectId, keepId: planItem.id);
        _updateAutoProgress(r.projectId);
        _touchProject(r.projectId);
        _auditPlanningIntegrity();
        _auditSessionIntegrity();
      });
      await _persist();
      await _offerDetailedProgress(r);
      await _waitForDialogTransition();
      await _showCoachFeedback(r);
      final coachChanged = _adaptRemainingWeekToReality();
      setState(() {});
      await _persist();
      _recordCoachDecision(r, coachChanged);
      await _persist();
      await _showCoachPlanningResult(r, coachChanged);
      await _showPlanVsRealized(r);
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
        _touchProject(r.projectId);
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
        _auditPlanningIntegrity();
        _auditSessionIntegrity();
      });
      await _persist();
      await _offerDetailedProgress(r);
      await _waitForDialogTransition();
      await _showCoachFeedback(r);
      final coachChanged = _adaptRemainingWeekToReality();
      setState(() {});
      await _persist();
      _recordCoachDecision(r, coachChanged);
      await _persist();
      await _showCoachPlanningResult(r, coachChanged);
      await _showPlanVsRealized(r);
    }
    _checkCelebrations();
  }

  /// Laisse la fermeture du dialogue de progression se terminer avant
  /// d'ouvrir le bilan suivant. Sur iPhone/Web, enchaîner deux showDialog
  /// dans la même frame peut laisser la barrière modale active et bloquer
  /// les boutons du dialogue suivant.
  Future<void> _waitForDialogTransition() async {
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
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
      session.newReading = result.reading;
      session.newHandsTogether = result.handsTogether;
      session.newMemory = result.memory;
      session.newInterpretation = result.interpretation;
      p.lastModified = DateTime.now();
    });
    await _persist();
  }

  /// Retour coach de fin de séance. Le choix reste volontairement très rapide :
  /// 3 boutons ; la conséquence est ensuite intégrée directement au planning.
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _syncCompletedPlanItemsForSession(Session s) {
    if (s.projectId == null) return;
    for (final item in plan) {
      if (item.projectId == s.projectId && _sameDay(item.date, s.date) && !item.completed && item.motsCles.contains('Coach')) {
        item.completed = true;
        item.sourceSessionId = s.id;
        item.duration = s.duration;
      }
    }
  }

  void _removeDuplicatePendingCoachPlans(String? projectId, {String? keepId}) {
    if (projectId == null) return;
    var kept = false;
    plan.removeWhere((item) {
      final isCandidate = item.projectId == projectId && !item.completed && item.motsCles.contains('Prochaine séance');
      if (!isCandidate) return false;
      if (keepId != null && item.id == keepId) return false;
      if (!kept) {
        kept = true;
        return false;
      }
      return true;
    });
  }

  void _auditPlanningIntegrity() {
    final seenCoach = <String>{};
    final seenIds = <String>{};
    plan.removeWhere((item) {
      if (!seenIds.add(item.id)) return true;
      if (item.duration < 1) item.duration = item.plannedDuration > 0 ? item.plannedDuration : 1;
      if (item.projectId == null || !item.motsCles.contains('Prochaine séance')) return false;
      final key = '${item.projectId}|${item.date.year}-${item.date.month}-${item.date.day}';
      if (seenCoach.add(key)) return false;
      return true;
    });
    plan.sort((a, b) => a.date.compareTo(b.date));
  }

  void _auditSessionIntegrity() {
    sessions.sort((a, b) => b.date.compareTo(a.date));
    final seen = <String>{};
    sessions.removeWhere((s) {
      if (seen.add(s.id)) return false;
      return true;
    });
  }

  Future<void> _showCoachFeedback(Session session) async {
    final projectId = session.projectId;
    if (projectId == null) return;
    final p = projectById(projectId);
    if (p == null) return;

    String weakestLabel() {
      final dims = <String, double>{
        'Lecture / mains séparées': p.reading,
        'Mains ensemble': p.handsTogether,
        'Mémorisation': p.memory,
        'Interprétation': p.interpretation,
      };
      return dims.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
    }

    String recommendation(String feeling) {
      final weakest = weakestLabel();
      final tempoGap = p.currentTempo > 0 && p.targetTempo > 0 && p.currentTempo < p.targetTempo;
      if (feeling == 'difficile') {
        if (tempoGap) return 'Reprendre $weakest à tempo réduit, puis remonter progressivement vers ${p.targetTempo} BPM.';
        return 'Reprendre $weakest sur un petit passage, lentement, pendant 15 à 20 min. Mieux vaut réussir peu mais proprement.';
      }
      if (feeling == 'facile') {
        if (weakestLabel() != 'Interprétation' && p.weakestStageValue >= .70) {
          return 'Le morceau est solide. Passe progressivement à l’interprétation et travaille les nuances.';
        }
        return 'Bonne séance. À la prochaine, garde $weakest mais augmente légèrement la difficulté ou le tempo.';
      }
      return 'Consolide encore $weakest pendant 15 à 20 min avant de passer à l’étape suivante.';
    }

    final feeling = await showDialog<String>(
      context: navKey.currentContext!,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Row(children: [Icon(Icons.auto_awesome), SizedBox(width: 8), Text('Bilan express')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p.emoji} ${p.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            const Text('Comment as-tu vécu cette séance ?', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(c, 'facile'),
                  icon: const Text('😊'),
                  label: const Align(alignment: Alignment.centerLeft, child: Text('Facile')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(c, 'correct'),
                  icon: const Text('😐'),
                  label: const Align(alignment: Alignment.centerLeft, child: Text('Correct')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(c, 'difficile'),
                  icon: const Text('😓'),
                  label: const Align(alignment: Alignment.centerLeft, child: Text('Difficile')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (feeling == null) return;
    session.coachFeeling = feeling;
    session.coachFocus = p.effectiveWorkFocus;
    session.coachRecommendation = recommendation(feeling);
    await _persist();

    // V140 / V154 : il n'existe plus de deuxième programme à valider ici.
    // Le coach expliquera sa décision et ajustera directement les séances futures
    // dans _adaptRemainingWeekToReality(), puis la décision sera inscrite au journal.
    // Le planning reste donc l'unique source d'action pour la prochaine séance.
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
      _touchProject(s.projectId);
      // Si le morceau repasse sous 100 % suite à cette suppression, on doit
      // pouvoir re-déclencher la célébration de fin de morceau plus tard.
      if (p != null && p.progress < 1) p.celebratedComplete = false;
      _auditPlanningIntegrity();
      _auditSessionIntegrity();
    });
    _persist();
  }

  Future<void> _scheduleCoachSession(PlanItem item) async {
    // Une recommandation du coach représente une seule prochaine séance.
    // Tant qu'elle n'est pas réalisée, on évite de la programmer plusieurs fois.
    final isCoachRecommendation = item.motsCles.contains('Prochaine séance');
    if (isCoachRecommendation && item.projectId != null) {
      final alreadyScheduled = plan.any((p) =>
          !p.completed &&
          p.projectId == item.projectId &&
          p.motsCles.contains('Prochaine séance') &&
          _sameDay(p.date, item.date));
      if (alreadyScheduled) {
        if (navKey.currentContext != null) {
          ScaffoldMessenger.of(navKey.currentContext!).showSnackBar(
            const SnackBar(content: Text('La prochaine séance de ce morceau est déjà programmée.')),
          );
        }
        return;
      }
    }
    setState(() {
      plan.add(item);
      _auditPlanningIntegrity();
    });
    _persist();
    if (navKey.currentContext != null) {
      ScaffoldMessenger.of(navKey.currentContext!).showSnackBar(
        SnackBar(content: Text('Séance ajoutée au planning : ${item.date.day}/${item.date.month} · ${item.duration} min')),
      );
    }
  }

  void _touchProject(String? projectId) {
    if (projectId == null) return;
    final p = projectById(projectId);
    if (p != null) p.lastModified = DateTime.now();
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
      builder: (_) => ProjectDialog(existing: existing, totalMinutesPracticed: totalMinutes, projectSessions: projectSessions, scheduledCoachSessions: plan.where((x) => x.projectId == existing?.id && !x.completed && x.motsCles.contains('Prochaine séance')).toList(), onScheduleCoachSession: _scheduleCoachSession, onRunThrough: startRunThrough),
    );
    if (r == null) return;
    setState(() {
      if (existing == null) {
        r.lastModified = DateTime.now();
        projects.add(r);
      } else {
        r.lastModified = DateTime.now();
        projects[projects.indexWhere((p) => p.id == existing.id)] = r;
      }
      // Une méthode utilisée par un projet doit toujours apparaître dans
      // la liste générale des méthodes, même si elle vient d'un ancien import.
      _syncMethodsFromUsage();
    });
    _persist();
    _checkCelebrations();
  }

  void duplicateProject(Project p) {
    // Une duplication crée une nouvelle fiche de travail indépendante.
    // On conserve les informations descriptives, mais le suivi d'avancement
    // repart à zéro pour éviter de donner au nouveau morceau l'impression
    // qu'il a déjà été travaillé.
    final copy = Project(
      id: newId(),
      name: p.name.trim().isEmpty ? 'Copie du morceau' : '${p.name} (copie)',
      progress: 0,
      goal: p.goal,
      method: p.method,
      priority: p.priority,
      workFocus: p.workFocus,
      workIntensity: p.workIntensity,
      status: 'À découvrir',
      statusIsManual: false,
      reading: 0,
      handsTogether: 0,
      memory: 0,
      interpretation: 0,
      currentTempo: 0,
      targetTempo: p.targetTempo,
      measures: p.measures,
      targetHours: p.targetHours,
      celebratedComplete: false,
      emoji: p.emoji,
      lastModified: DateTime.now(),
    );
    setState(() {
      projects.insert(0, copy);
      _syncMethodsFromUsage();
    });
    _persist();
    if (navKey.currentContext != null) {
      ScaffoldMessenger.of(navKey.currentContext!).showSnackBar(
        SnackBar(content: Text('Morceau dupliqué : ${copy.name}')),
      );
    }
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
      coachFocus: x.motsCles.where((t) => t != 'Coach' && t != 'Prochaine séance').firstOrNull,
      coachRecommendation: x.motsCles.contains('Coach') ? x.details : null,
      plannedDuration: x.duration,
      plannedTempo: x.projectId == null ? null : projectById(x.projectId)?.currentTempo,
    );
    setState(() {
      x.completed = true;
      _capturePreviousProgress(newSession);
      sessions.insert(0, newSession);
      x.sourceSessionId = newSession.id;
      _updateAutoProgress(x.projectId);
      _touchProject(x.projectId);
    });
    _persist();
    await _offerDetailedProgress(newSession);
    await _waitForDialogTransition();
    await _showCoachFeedback(newSession);
    final coachChanged = _adaptRemainingWeekToReality();
    setState(() {});
    await _persist();
    _recordCoachDecision(newSession, coachChanged);
    await _persist();
    await _showCoachPlanningResult(newSession, coachChanged);
    await _showPlanVsRealized(newSession);
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
      CoachHome(
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
        onOpenProgress: openProgressDashboard,
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
        onResetPracticeBase: resetPracticeBase,
        projectById: projectById,
        now: _clockNow,
        onOrientSuggestion: orientSuggestion,
        onOrientSuggestionThisWeek: orientSuggestionThisWeek,
        latestCoachDecision: coachDecisionLog.isEmpty ? null : coachDecisionLog.reduce((a, b) => a.date.isAfter(b.date) ? a : b),
        onOpenCoachLog: _showCoachDecisionLog,
      ),
      Sessions(
        items: sessions,
        onAdd: () => addOrEditSession(),
        onEdit: addOrEditSession,
        onDelete: deleteSession,
        projectById: projectById,
        onOpenProject: (p) => addOrEditProject(p),
      ),
      Projects(items: projects, sessions: sessions, onAdd: () => addOrEditProject(), onEdit: addOrEditProject, onDelete: deleteProject, onDuplicate: duplicateProject),
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
        onCoachAdjustmentSeen: (item) {
          setState(() {});
          _persist();
        },
        projectById: projectById,
        sessions: sessions,
        onOpenCoachLog: _showCoachDecisionLog,
        coachRestDayKeys: coachRestDayKeys,
        dailyCapacity: dailyCapacity,
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B50D6), brightness: Brightness.light),
        brightness: Brightness.light,
        visualDensity: VisualDensity.standard,
        scaffoldBackgroundColor: const Color(0xFFF3F5FA),
        dividerTheme: const DividerThemeData(space: 20, thickness: 1, indent: 0, endIndent: 0),
        listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2), minLeadingWidth: 34),
        dialogTheme: DialogThemeData(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.2),
        ),
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(width: 1.5, color: Colors.indigo),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 70,
          elevation: 6,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          indicatorColor: const Color(0xFFDDD9FF),
          labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B82FF), brightness: Brightness.dark),
        brightness: Brightness.dark,
        visualDensity: VisualDensity.standard,
        dividerTheme: const DividerThemeData(space: 20, thickness: 1, indent: 0, endIndent: 0),
        listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2), minLeadingWidth: 34),
        dialogTheme: DialogThemeData(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.2),
        ),
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(width: 1.5, color: Colors.indigoAccent),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 70,
          elevation: 6,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          indicatorColor: const Color(0xFF3E3966),
          labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
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
  const CardBox({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    final compactPhone = MediaQuery.sizeOf(c).width < 430;
    final cardRadius = compactPhone ? 16.0 : 20.0;
    final cardPadding = compactPhone && padding == const EdgeInsets.all(18)
        ? const EdgeInsets.all(14)
        : padding;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(cardRadius),
        border: Border.all(color: scheme.outlineVariant.withOpacity(.42)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: scheme.primary.withOpacity(.72)),
          Expanded(
            child: Padding(
              padding: cardPadding,
              child: Theme(
                data: Theme.of(c).copyWith(
                  cardTheme: Theme.of(c).cardTheme.copyWith(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: Colors.transparent,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chrono / minuteur de pratique
// ---------------------------------------------------------------------------

class PracticeTimerScreen extends StatefulWidget {
  const PracticeTimerScreen({super.key, this.title = 'Chrono de pratique', this.subtitle});
  final String title;
  final String? subtitle;
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
        if (!mounted) {
          _timer?.cancel();
          return;
        }
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
    if (!mounted) return;
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
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.subtitle != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Theme.of(c).colorScheme.secondaryContainer.withOpacity(.55),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.music_note_outlined, size: 20, color: Theme.of(c).colorScheme.secondary),
                    const SizedBox(width: 9),
                    Expanded(child: Text(widget.subtitle!, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                  ]),
                ),
                const SizedBox(height: 18),
              ],
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
                        running = false;
                        final minutes = (elapsedSeconds / 60).round();
                        if (mounted) Navigator.of(context).pop(minutes < 1 ? 1 : minutes);
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
      borderRadius: BorderRadius.circular(18),
      color: scheme.primaryContainer.withOpacity(.24),
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
      width: 34, height: 34, alignment: Alignment.center,
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
    required this.plannedMinutes,
    required this.realizedPlannedMinutes,
    required this.plannedSessions,
    required this.completedPlannedSessions,
    required this.pieces,
    required this.bestDay,
    required this.bestDayMinutes,
    required this.daysPracticed,
    required this.avgRating,
  });
  final DateTime weekStart;
  final int totalMinutes;
  final int plannedMinutes;
  final int realizedPlannedMinutes;
  final int plannedSessions;
  final int completedPlannedSessions;
  final List<MapEntry<Project, int>> pieces;
  final DateTime? bestDay;
  final int bestDayMinutes;
  final int daysPracticed;
  final double? avgRating;
}

class AppBadge {
  AppBadge(this.id, this.emoji, this.title, this.description, this.earned, {this.progress = 0, this.target = 1});
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool earned;
  final int progress;
  final int target;
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

String _formatDateTimeFr(DateTime d) {
  const months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year} · $hh:$mm';
}

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
    required this.onResetPracticeBase,
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
  final Future<void> Function() onResetPracticeBase;
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
          const Divider(),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(dc);
              await onResetPracticeBase();
            },
            child: const Row(children: [
              Icon(Icons.restart_alt_outlined),
              SizedBox(width: 12),
              Expanded(child: Text('Préparer une base de test propre')),
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

// ---------------------------------------------------------------------------
// Accueil = coach quotidien
// ---------------------------------------------------------------------------
class _CoachPieceCandidate {
  const _CoachPieceCandidate({
    required this.project,
    required this.score,
    required this.reason,
    required this.action,
    required this.lastLabel,
    required this.secondarySignal,
  });

  final Project project;
  final int score;
  final String reason;
  final String action;
  final String lastLabel;
  final String secondarySignal;
}

class CoachHome extends StatelessWidget {
  const CoachHome({
    super.key,
    required this.projects, required this.sessions, required this.plan,
    required this.minutes, required this.weeklyTarget, required this.streak,
    required this.suggestions, required this.challenges, required this.challengeProgress,
    required this.badges, required this.onOpenBadges, required this.onOpenBilan, required this.onOpenProgress,
    required this.onStart, required this.onTogglePlan, required this.onEditCapacity,
    required this.onQuickProject, required this.onQuickPlan, required this.onExport,
    required this.darkMode, required this.onToggleDarkMode, required this.onImport,
    required this.onResetPracticeBase,
    required this.projectById, required this.now, required this.onOrientSuggestion, required this.onOrientSuggestionThisWeek,
    required this.latestCoachDecision, required this.onOpenCoachLog,
  });
  final List<Project> projects; final List<Session> sessions; final List<PlanItem> plan;
  final int minutes; final int weeklyTarget; final int streak;
  final List<Suggestion> suggestions; final List<Challenge> challenges;
  final int Function(Challenge) challengeProgress; final List<AppBadge> badges;
  final VoidCallback onOpenBadges; final VoidCallback onOpenBilan; final VoidCallback onOpenProgress;
  final void Function([PlanItem?]) onStart; final void Function(PlanItem) onTogglePlan;
  final VoidCallback onEditCapacity; final VoidCallback onQuickProject; final VoidCallback onQuickPlan;
  final VoidCallback onExport; final bool darkMode; final VoidCallback onToggleDarkMode; final VoidCallback onImport;
  final Future<void> Function() onResetPracticeBase;
  final Project? Function(String?) projectById; final DateTime now; final void Function(String) onOrientSuggestion;
  final Future<void> Function(String) onOrientSuggestionThisWeek;
  final CoachDecision? latestCoachDecision;
  final VoidCallback onOpenCoachLog;

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime? _lastSession(String projectId) {
    DateTime? last;
    for (final s in sessions) {
      if (s.projectId == projectId && (last == null || s.date.isAfter(last!))) last = s.date;
    }
    return last;
  }

  double _weakestStage(Project p) => [p.reading, p.handsTogether, p.memory, p.interpretation].reduce(math.min);

  String _focusFor(Project p) => p.workFocus == 'Automatique' ? p.effectiveWorkFocus : p.workFocus;

  Session? _lastProjectSession(String projectId) {
    Session? last;
    for (final s in sessions) {
      if (s.projectId == projectId && (last == null || s.date.isAfter(last!.date))) last = s;
    }
    return last;
  }

  String? _lastFeeling(String projectId) => _lastProjectSession(projectId)?.coachFeeling;

  int _recentDifficultSessions(String projectId) {
    final recent = sessions
        .where((s) => s.projectId == projectId && s.coachFeeling != null)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return recent.take(3).where((s) => s.coachFeeling == 'difficile').length;
  }

  String _coachLastLabel(Project p) {
    final last = _lastProjectSession(p.id);
    if (last == null) return 'Jamais travaillé';
    final days = _day(now).difference(_day(last.date)).inDays;
    if (days <= 0) return 'Travaillé aujourd’hui';
    if (days == 1) return 'Vu hier';
    return 'Vu il y a $days j';
  }

  _CoachPieceCandidate? _candidateFor(Project p) {
    if (p.effectiveStatus == 'Répertoire d’entretien' || p.progress >= 1) return null;

    final last = _lastProjectSession(p.id);
    final days = last == null ? null : _day(now).difference(_day(last.date)).inDays;
    final weakest = _weakestStage(p);
    final difficult = _recentDifficultSessions(p.id);
    final lastFeeling = last?.coachFeeling;
    final runs = sessions.where((s) => s.projectId == p.id && s.type == 'Run-through').toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final lastRun = runs.isEmpty ? null : runs.first;
    final interruptedRun = lastRun?.runThroughCompleted == false;

    var score = 0;
    if (p.priority) score += 34;
    score += ((1 - p.progress).clamp(0.0, 1.0) * 24).round();
    score += ((1 - weakest).clamp(0.0, 1.0) * 22).round();
    if (days == null) {
      score += 10;
    } else {
      score += math.min(days * 3, 27);
    }
    if (lastFeeling == 'difficile') score += 14;
    if (difficult >= 2) score += 12;
    if (interruptedRun) score += 22;
    if (p.targetTempo > 0 && p.currentTempo > 0 && p.currentTempo < p.targetTempo) score += 6;

    // Une séance déjà prévue aujourd’hui reste visible, mais passe légèrement
    // derrière un morceau réellement en attente afin de favoriser la variété.
    final todayPending = plan.any((x) => !x.completed && _day(x.date) == _day(now) && x.projectId == p.id);
    final todayDone = plan.any((x) => x.completed && _day(x.date) == _day(now) && x.projectId == p.id);
    if (todayDone) score -= 12;
    else if (todayPending) score += 3;

    String reason;
    if (interruptedRun) {
      final stop = lastRun!.runThroughStopNote?.trim();
      reason = stop == null || stop.isEmpty
          ? 'Dernier Run-through interrompu : la continuité est à sécuriser.'
          : 'Dernier Run-through interrompu : reprendre le point d’arrêt « $stop ». ';
    } else if (lastFeeling == 'difficile' || difficult >= 2) {
      reason = difficult >= 2
          ? 'Plusieurs séances récentes ont été difficiles : le coach privilégie la consolidation.'
          : 'Dernière séance difficile : le coach réduit la pression et consolide.';
    } else if (p.priority && (days == null || days >= 4)) {
      reason = days == null
          ? 'Morceau prioritaire encore peu travaillé.'
          : 'Morceau prioritaire absent depuis $days jours.';
    } else if (days != null && days >= 5) {
      reason = 'Pas travaillé depuis $days jours : une reprise évite de perdre le fil.';
    } else if (weakest < .55) {
      reason = 'L’étape la plus fragile est ${p.weakestStageName} (${(weakest * 100).round()} %).';
    } else if (p.targetTempo > 0 && p.currentTempo > 0 && p.currentTempo < p.targetTempo) {
      reason = 'Le tempo reste à construire : ${p.currentTempo} → ${p.targetTempo} BPM.';
    } else if (days == null) {
      reason = 'Le morceau n’a pas encore de séance enregistrée : il faut lancer sa progression.';
    } else {
      reason = 'Le moteur combine progression, étape faible, régularité et ressenti pour le remettre en mouvement.';
    }

    final focus = _focusFor(p);
    String action;
    if (interruptedRun) {
      action = 'Reprendre ${p.weakestStageName.toLowerCase()} avant un nouveau Run-through';
    } else if (lastFeeling == 'difficile' || difficult >= 2) {
      action = 'Consolider ${focus.toLowerCase()} à charge légère';
    } else if (p.targetTempo > 0 && p.currentTempo > 0 && p.currentTempo < p.targetTempo && focus == 'Automatique') {
      action = 'Travailler le tempo à ${p.currentTempo} BPM';
    } else {
      action = 'Travailler ${focus.toLowerCase()}';
    }

    final secondary = [
      if (p.priority) 'Prioritaire',
      if (days != null && days >= 4) '$days j sans séance',
      if (difficult > 0) '$difficult difficile${difficult > 1 ? 's' : ''}',
      if (p.progress > 0) '${(p.progress * 100).round()} % global',
    ].take(2).join(' · ');

    return _CoachPieceCandidate(
      project: p,
      score: score,
      reason: reason,
      action: action,
      lastLabel: _coachLastLabel(p),
      secondarySignal: secondary,
    );
  }

  List<_CoachPieceCandidate> _coachCandidates() {
    final result = <_CoachPieceCandidate>[];
    for (final p in projects) {
      final candidate = _candidateFor(p);
      if (candidate != null) result.add(candidate);
    }
    result.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final priority = (b.project.priority ? 1 : 0).compareTo(a.project.priority ? 1 : 0);
      if (priority != 0) return priority;
      return a.project.lastModified.compareTo(b.project.lastModified);
    });
    return result.take(3).toList();
  }

  int _recommendedMinutesForHome(Project p) {
    final last = _lastProjectSession(p.id);
    final feeling = last?.coachFeeling;
    var minutes = feeling == 'difficile' || _recentDifficultSessions(p.id) >= 2 ? 15 : (feeling == 'facile' ? 25 : 20);
    return minutes.clamp(10, 25).toInt();
  }

  String _decisionDateLabel(CoachDecision d) {
    final v = d.date.toLocal();
    return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')} · ${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
  }

  String _feelingLabel(String? feeling) {
    switch (feeling) {
      case 'facile': return '😊 Facile';
      case 'difficile': return '😓 Difficile';
      case 'correct': return '😐 Correct';
      default: return '';
    }
  }

  String _adaptiveAdvice(Project p) {
    final last = _lastFeeling(p.id);
    final difficult = _recentDifficultSessions(p.id);
    final lastRun = [...sessions.where((s) => s.projectId == p.id && s.type == 'Run-through')]
      ..sort((a, b) => b.date.compareTo(a.date));
    if (lastRun.isNotEmpty) {
      final rt = lastRun.first;
      if (rt.runThroughCompleted == false) {
        return 'Dernier run-through interrompu : le prochain travail doit sécuriser le passage d’arrêt avant de relancer une exécution complète.';
      }
      final target = p.targetTempo;
      final end = rt.runThroughEndTempo ?? 0;
      if (target > 0 && end > 0 && end < target * .9) {
        return 'Run-through terminé mais encore nettement sous le tempo cible : consolide la continuité avant de pousser la vitesse.';
      }
    }
    if (difficult >= 2) return 'Le coach allège la prochaine reprise : petit passage, tempo confortable, puis progression.';
    if (last == 'difficile') return 'Dernière séance difficile : on consolide avant d’augmenter la difficulté.';
    if (last == 'facile') return 'Dernière séance facile : tu peux légèrement augmenter la difficulté ou le tempo.';
    if (last == 'correct') return 'Dernière séance correcte : on consolide encore avant de pousser.';
    return 'Pas encore de ressenti enregistré : le coach va apprendre de cette séance.';
  }

  String _whyToday(Project p, DateTime now) {
    final last = _lastSession(p.id);
    final days = last == null ? null : now.difference(last).inDays;
    final weakest = _weakestStage(p);
    final feeling = _lastFeeling(p.id);
    final difficultCount = _recentDifficultSessions(p.id);
    String stage;
    if (weakest == p.reading) stage = 'lecture';
    else if (weakest == p.handsTogether) stage = 'mains ensemble';
    else if (weakest == p.memory) stage = 'mémorisation';
    else stage = 'interprétation';

    if (difficultCount >= 2) return 'Deux des dernières séances ont été difficiles : on consolide ce morceau avec une charge plus légère.';
    final latestRun = [...sessions.where((s) => s.projectId == p.id && s.type == 'Run-through')]..sort((a, b) => b.date.compareTo(a.date));
    if (latestRun.isNotEmpty && latestRun.first.runThroughCompleted == false) {
      final stop = latestRun.first.runThroughStopNote?.trim();
      return stop == null || stop.isEmpty
          ? 'Dernier run-through interrompu : on travaille la continuité avant de refaire une exécution complète.'
          : 'Dernier run-through interrompu au point indiqué : $stop. C’est la cible prioritaire avant le prochain run-through.';
    }
    if (feeling == 'difficile') return 'Dernière séance difficile : le coach préfère consolider avant de demander plus de vitesse ou de difficulté.';
    if (feeling == 'facile') return 'Dernière séance facile : c’est le bon moment pour faire progresser légèrement l’objectif.';
    if (p.effectiveStatus == 'Répertoire d’entretien') {
      if (days != null && days >= 14) return 'Répertoire d’entretien à revoir : $days jours depuis la dernière séance.';
      return 'Une courte révision entretient ce morceau sans alourdir ton programme.';
    }
    if (p.priority && days != null && days >= 4) return 'Morceau prioritaire et absent depuis $days jours : il mérite de reprendre sa place aujourd’hui.';
    if (p.priority) return 'Morceau prioritaire : on protège sa progression avec une séance ciblée.';
    if (weakest < 0.55) return 'L’étape la plus fragile est $stage (${(weakest * 100).round()} %) : c’est le meilleur levier de progression.';
    if (days != null && days >= 5) return 'Cela fait $days jours que tu ne l’as pas travaillé : une reprise maintenant évite qu’il recule.';
    if (p.targetTempo > 0 && p.currentTempo > 0 && p.currentTempo < p.targetTempo) return 'Le tempo est encore à construire : ${p.currentTempo} → ${p.targetTempo} BPM.';
    if (p.progress < 0.5) return 'Le morceau est encore en construction (${(p.progress * 100).round()} %) : une séance ciblée fera avancer le plus.';
    return 'Une séance ciblée sur ${_focusFor(p).toLowerCase()} est aujourd’hui le meilleur usage de ton temps.';
  }

  int _recentPracticeMinutes({int days = 7}) {
    final now = DateTime.now();
    return sessions
        .where((s) {
          final age = now.difference(s.date);
          return !age.isNegative && age <= Duration(days: days);
        })
        .fold<int>(0, (sum, s) => sum + s.duration);
  }

  int _recentFocusCount(String projectId, String focus, {int days = 7}) {
    final now = DateTime.now();
    return sessions.where((s) {
      if (s.projectId != projectId || s.coachFocus != focus) return false;
      final age = now.difference(s.date);
      return !age.isNegative && age <= Duration(days: days);
    }).length;
  }

  int _coachScore(PlanItem item, Project? p, DateTime now) {
    if (p == null) return 10;
    var score = 0;
    if (p.priority) score += 40;
    score += ((1 - p.progress).clamp(0.0, 1.0) * 25).round();
    score += ((1 - _weakestStage(p)).clamp(0.0, 1.0) * 25).round();
    final last = _lastSession(p.id);
    if (last == null) score += 12;
    else {
      final days = now.difference(last).inDays;
      score += math.min(days * 3, 30);
      if (p.effectiveStatus == 'Répertoire d’entretien' && days >= 14) score += 35;
    }
    if (item.category == 'Répertoire d’entretien') score += 20;
    if (_focusFor(p) == 'Passages difficiles' || _focusFor(p) == 'Mains ensemble' || _focusFor(p) == 'Rythme') score += 6;
    final feeling = _lastFeeling(p.id);
    if (feeling == 'difficile') score += 18;
    if (feeling == 'facile') score += 5;
    if (_recentDifficultSessions(p.id) >= 2) score += 18;

    // V139 : la charge réellement absorbée et la variété récente comptent
    // davantage dans le classement, sans annuler la priorité du morceau.
    final recentMinutes = _recentPracticeMinutes(days: 7);
    if (weeklyTarget > 0) {
      final loadRatio = recentMinutes / weeklyTarget;
      if (loadRatio >= 1.15 && !p.priority) score -= 8;
      if (loadRatio < .55 && p.priority) score += 4;
    }
    final focus = _focusFor(p);
    final repeatedFocus = _recentFocusCount(p.id, focus, days: 4);
    if (repeatedFocus >= 2) score -= 6;
    if (repeatedFocus == 0) score += 3;
    return score;
  }

  PlanItem? _bestPending(List<PlanItem> items, DateTime now) {
    if (items.isEmpty) return null;

    // V117 : une action terminée aujourd'hui ne doit plus revenir immédiatement
    // en tête du coach. On l'écarte seulement s'il existe une vraie alternative ;
    // cela évite aussi de se retrouver sans mission lorsqu'il n'y a qu'un morceau.
    final today = _day(now);
    final completedTodayProjects = plan
        .where((x) => x.completed && _day(x.date) == today && x.projectId != null)
        .map((x) => x.projectId!)
        .toSet();
    final alternatives = items.where((x) => x.projectId == null || !completedTodayProjects.contains(x.projectId)).toList();
    final candidates = alternatives.isNotEmpty ? alternatives : [...items];

    String? lastFocusToday(String? projectId) {
      if (projectId == null) return null;
      final done = plan
          .where((x) => x.completed && _day(x.date) == today && x.projectId == projectId)
          .toList()
        ..sort((a, b) => b.id.compareTo(a.id));
      if (done.isEmpty) return null;
      final source = done.first.sourceSessionId;
      if (source == null) return null;
      return sessions.where((s) => s.id == source).firstOrNull?.coachFocus;
    }

    final ranked = [...candidates];
    ranked.sort((a, b) {
      final pa = projectById(a.projectId);
      final pb = projectById(b.projectId);
      var sa = _coachScore(a, pa, now).toDouble();
      var sb = _coachScore(b, pb, now).toDouble();
      if (pa != null && a.projectId != null && lastFocusToday(a.projectId) == _focusFor(pa)) sa -= 14;
      if (pb != null && b.projectId != null && lastFocusToday(b.projectId) == _focusFor(pb)) sb -= 14;
      // V117 : léger bonus de variété entre morceaux de même priorité.
      if (pa != null && pb != null && a.projectId != b.projectId) {
        if (completedTodayProjects.contains(a.projectId)) sa -= 8;
        if (completedTodayProjects.contains(b.projectId)) sb -= 8;
      }
      if (sa != sb) return sb.compareTo(sa);
      return a.id.compareTo(b.id);
    });
    return ranked.first;
  }

  List<Session> _recentPlannedSessions(String projectId) {
    final list = sessions.where((s) => s.projectId == projectId && s.plannedDuration != null).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list.take(3).toList();
  }

  double? _plannedDurationAdherence(Project p) {
    final recent = _recentPlannedSessions(p.id).where((s) => s.plannedDuration! > 0).toList();
    if (recent.isEmpty) return null;
    final ratios = recent.map((s) => s.duration / s.plannedDuration!).toList();
    return ratios.fold<double>(0, (a, b) => a + b) / ratios.length;
  }

  String _durationAdjustmentHint(Project p) {
    final adherence = _plannedDurationAdherence(p);
    if (adherence == null) return '';
    if (adherence < .80) return 'Les dernières séances ont été plus courtes que prévu : le coach allège légèrement la prochaine séance.';
    if (adherence > 1.20 && _lastFeeling(p.id) != 'difficile') return 'Tu dépasses régulièrement le temps prévu sans signal de difficulté : le coach peut augmenter légèrement la charge.';
    return '';
  }

  int _recommendedMinutes(Project p) {
    final feeling = _lastFeeling(p.id);
    var minutes = feeling == 'difficile' || _recentDifficultSessions(p.id) >= 2 ? 15 : (feeling == 'facile' ? 25 : 20);
    final adherence = _plannedDurationAdherence(p);
    if (adherence != null) {
      if (adherence < .80) {
        minutes -= 5;
      } else if (adherence > 1.20 && feeling != 'difficile') {
        minutes += 5;
      }
    }
    // V117 : les habitudes réelles priment sur une durée théorique fixe.
    if (adherence != null && adherence >= .92 && feeling != 'difficile') minutes += 2;
    if (adherence != null && adherence <= .72) minutes -= 2;
    return minutes.clamp(10, 30).toInt();
  }

  String _recommendedFocus(Project p) => _focusFor(p);

  int? _recommendedTempo(Project p) {
    if (p.currentTempo <= 0) return null;
    final feeling = _lastFeeling(p.id);
    var tempo = p.currentTempo;
    if (_recentDifficultSessions(p.id) >= 2 || feeling == 'difficile') {
      tempo = math.max(1, tempo - 5);
    } else {
      final recent = _recentPlannedSessions(p.id).where((s) => s.plannedTempo != null && s.newTempo != null).toList();
      if (recent.isNotEmpty) {
        final averageDelta = recent.fold<double>(0, (a, s) => a + (s.newTempo! - s.plannedTempo!)) / recent.length;
        if (averageDelta >= 3 && feeling == 'facile') tempo += 3;
        if (averageDelta <= -5 && feeling != 'facile') tempo = math.max(1, tempo - 3);
      }
    }
    return tempo;
  }

  int? _tempoFromPlanDetails(String details) {
    final match = RegExp(r'(\d+)\s*BPM', caseSensitive: false).firstMatch(details);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String _coachMessage(DateTime now, PlanItem? next) {
    if (next != null) {
      final p = projectById(next.projectId);
      if (p != null) {
        final focus = p.workFocus == 'Automatique' ? p.effectiveWorkFocus : p.workFocus;
        return '${workFocusEmoji(focus)} Aujourd’hui, on avance sur ${p.name} avec un objectif clair : $focus.';
      }
      return '🎹 Une séance est prête. Commence simplement : la régularité compte plus que la séance parfaite.';
    }
    if (suggestions.isNotEmpty) return '💡 ${suggestions.first.text}';
    if (streak >= 7) return '🔥 Ta régularité est excellente. Garde le rythme sans augmenter inutilement la charge.';
    if (streak >= 3) return '👏 Belle régularité. Une séance courte aujourd’hui suffit à entretenir l’élan.';
    if (now.hour < 12) return '☀️ Commence par le morceau qui demande le plus de concentration.';
    if (now.hour < 18) return '🎹 Une séance ciblée vaut mieux qu’une longue séance dispersée.';
    return '🌙 Fais simple ce soir : un objectif précis, puis arrête-toi sur une bonne sensation.';
  }

  @override
  Widget build(BuildContext c) {
    final now = this.now;
    final today = _day(now);
    final todayItems = plan.where((x) => _day(x.date) == today).toList()
      ..sort((a, b) => a.completed == b.completed ? a.id.compareTo(b.id) : (a.completed ? 1 : -1));
    final pending = todayItems.where((x) => !x.completed).toList();
    final todayTarget = todayItems.fold(0, (a, x) => a + x.duration);
    int realizedFor(PlanItem x) => x.sourceSessionId == null
        ? 0
        : sessions.where((s) => s.id == x.sourceSessionId).firstOrNull?.duration ?? 0;
    final todayDone = todayItems.where((x) => x.completed).fold(0, (a, x) => a + realizedFor(x));
    final todayRatio = todayTarget == 0 ? 0.0 : (todayDone / todayTarget).clamp(0.0, 1.0).toDouble();
    final weeklyRatio = weeklyTarget == 0 ? 0.0 : (minutes / weeklyTarget).clamp(0.0, 1.0).toDouble();
    final next = _bestPending(pending, now);
    final nextProject = next == null ? null : projectById(next.projectId);
    final coachPieces = _coachCandidates();
    final badgeCount = badges.where((b) => b.earned).length;

    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_greeting(now, streak), style: Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('Ton coach piano · ${todayItems.isEmpty ? 'séance libre possible' : '${pending.length} séance${pending.length > 1 ? 's' : ''} à faire'}', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.schedule, size: 14, color: Theme.of(c).colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(_formatDateTimeFr(now), style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant)),
            const SizedBox(width: 10),
            Text('V$appVersion', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.primary)),
          ]),
        ])),
        IconButton(onPressed: () => _showSettings(c), icon: const Icon(Icons.settings_outlined), tooltip: 'Réglages'),
      ]),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(c).colorScheme.surfaceContainerHighest.withOpacity(.58),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.sync_alt_outlined, size: 18, color: Theme.of(c).colorScheme.primary),
          const SizedBox(width: 9),
          Expanded(child: Text(
            'Le planning organise ta semaine. Le coach ajuste les jours à venir selon ce que tu as réellement joué.',
            style: TextStyle(fontSize: 12, height: 1.3, color: Theme.of(c).colorScheme.onSurfaceVariant),
          )),
        ]),
      ),
      const SizedBox(height: 12),

      CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: Theme.of(c).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.auto_awesome, color: Theme.of(c).colorScheme.onPrimaryContainer)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MISSION DU JOUR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.3, color: Theme.of(c).colorScheme.primary)),
            SizedBox(height: 3), Text('Une séance utile, maintenant', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ])),
        ]),
        const SizedBox(height: 14),
        if (next != null) ...[
          Text(next.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (nextProject != null) ...[const SizedBox(height: 5), Text('${nextProject!.emoji} ${nextProject!.name}', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant))],
          if (next.details.isNotEmpty) ...[const SizedBox(height: 6), Text(next.details, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant))],
          if (nextProject != null) ...[
            const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(c).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline, size: 20, color: Theme.of(c).colorScheme.primary), const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('POURQUOI AUJOURD’HUI ?', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .8)),
                const SizedBox(height: 4),
                Text(_whyToday(nextProject!, now), style: const TextStyle(fontSize: 13, height: 1.3)),
              ])),
            ])),
          ],
          if (nextProject != null && _lastFeeling(nextProject!.id) != null) ...[
            const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(c).colorScheme.outlineVariant)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.psychology_outlined, size: 20), const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DERNIER BILAN · ${_feelingLabel(_lastFeeling(nextProject!.id))}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .7)),
                const SizedBox(height: 4),
                Text(_adaptiveAdvice(nextProject!), style: const TextStyle(fontSize: 13, height: 1.3)),
              ])),
            ])),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(avatar: const Icon(Icons.timer_outlined, size: 16), label: Text('${next.duration} min')),
            if (nextProject != null) Chip(avatar: Text(workFocusEmoji(nextProject!.workFocus == 'Automatique' ? nextProject!.effectiveWorkFocus : nextProject!.workFocus)), label: Text(nextProject!.workFocus == 'Automatique' ? nextProject!.effectiveWorkFocus : nextProject!.workFocus)),
          ]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => onStart(next), icon: const Icon(Icons.play_arrow_rounded), label: const Text('COMMENCER MAINTENANT'))),
        ] else if (todayItems.isEmpty) ...[
          const Text('Ton planning est vide pour aujourd’hui.'), const SizedBox(height: 6),
          Text(_coachMessage(now, null), style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)), const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: onStart, icon: const Icon(Icons.play_arrow_rounded), label: const Text('FAIRE UNE SESSION LIBRE'))),
        ] else ...[
          const Text('🎉 Programme du jour terminé.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 5),
          Text('Tu peux t’arrêter ici, ou faire une courte session libre.', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)), const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: onStart, icon: const Icon(Icons.add), label: const Text('Session libre')),
        ],
      ])),

      const SizedBox(height: 14),
      CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.psychology_outlined, size: 20, color: Theme.of(c).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('COACH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Theme.of(c).colorScheme.primary)),
            const SizedBox(height: 4),
            if (latestCoachDecision == null) ...[
              const Text('Aucune analyse récente.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('La prochaine analyse apparaîtra après ta prochaine séance.', style: TextStyle(fontSize: 12.5, height: 1.3, color: Theme.of(c).colorScheme.onSurfaceVariant)),
            ] else ...[
              const Text('DERNIÈRE ANALYSE DU COACH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .7)),
              const SizedBox(height: 5),
              Text(latestCoachDecision!.message, style: const TextStyle(fontSize: 13.5, height: 1.35)),
              if ((latestCoachDecision!.reason ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text('Pourquoi : ${latestCoachDecision!.reason}', style: TextStyle(fontSize: 11.5, height: 1.3, color: Theme.of(c).colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 4),
              Text(_decisionDateLabel(latestCoachDecision!), style: TextStyle(fontSize: 10.5, color: Theme.of(c).colorScheme.onSurfaceVariant)),
            ],
          ])),
          if (latestCoachDecision != null)
            IconButton(
              tooltip: 'Ouvrir le journal du coach',
              onPressed: onOpenCoachLog,
              icon: const Icon(Icons.chevron_right),
            ),
        ]),
      ])),

      const SizedBox(height: 14),
      Row(children: [Expanded(child: _stat(c, Icons.today, 'Aujourd’hui', '$todayDone / $todayTarget min', todayRatio)), const SizedBox(width: 10), Expanded(child: _stat(c, Icons.calendar_month, 'Cette semaine', '$minutes / $weeklyTarget min', weeklyRatio))]),

      const SizedBox(height: 18),
      Row(children: [Expanded(child: Text('Ton programme', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))), if (todayItems.isNotEmpty) Text('${todayItems.length} activité${todayItems.length > 1 ? 's' : ''}', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 12))]),
      const SizedBox(height: 8),
      CardBox(child: todayItems.isEmpty ? const Text('Aucune activité prévue.') : Column(children: [
        ...todayItems.take(5).map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Tooltip(
              message: item.completed ? 'Séance réalisée' : 'Marquer comme fait',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: item.completed ? null : () => onTogglePlan(item),
                disabledColor: Colors.green.shade600,
                icon: Icon(item.completed ? Icons.check_circle : Icons.circle_outlined),
                color: item.completed ? Colors.green : categoryColor(item.category),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: item.completed ? null : () => onTogglePlan(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, style: TextStyle(fontWeight: FontWeight.w700, decoration: item.completed ? TextDecoration.lineThrough : null)),
                  if (item.details.isNotEmpty) Text(item.details, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                ]),
              ),
            )),
            Text('${item.duration} min', style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant)),
            if (!item.completed)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => onStart(item),
                icon: const Icon(Icons.play_circle_outline),
                tooltip: 'Démarrer cette séance',
              )
            else
              const SizedBox(width: 48),
          ]),
        )),
      ])),

      if (coachPieces.isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('Les morceaux à faire avancer', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          Text('Coach · top ${coachPieces.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: 5),
        Text('Cette liste est calculée à partir du besoin réel du morceau, de sa progression, de la régularité et du ressenti.', style: TextStyle(fontSize: 11.5, color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.3)),
        const SizedBox(height: 8),
        ...coachPieces.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.project.emoji, style: const TextStyle(fontSize: 25)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(item.project.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  if (item.project.priority) const Icon(Icons.star, size: 17, color: Colors.amber),
                ]),
                const SizedBox(height: 5),
                progress(item.project.progress),
                const SizedBox(height: 5),
                Text('${(item.project.progress * 100).round()} % · ${workFocusEmoji(_focusFor(item.project))} ${_focusFor(item.project)}', style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant)),
              ])),
            ],),
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(c).colorScheme.surfaceContainerHighest.withOpacity(.62),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('POURQUOI ?', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: .8, color: Theme.of(c).colorScheme.primary)),
                const SizedBox(height: 3),
                Text(item.reason, style: const TextStyle(fontSize: 12.5, height: 1.3)),
                const SizedBox(height: 6),
                Text('${workFocusEmoji(_focusFor(item.project))} ${item.action}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.primary)),
              ]),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text([item.lastLabel, item.secondarySignal].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(fontSize: 10.5, color: Theme.of(c).colorScheme.onSurfaceVariant))),
              Text('Dans le planning', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.primary)),
            ]),
          ])),
        )),
      ],

      const SizedBox(height: 18),
      Row(children: [
          Expanded(child: _action('Bilan', Icons.insights, onOpenBilan)),
          const SizedBox(width: 6),
          Expanded(child: _action('Progression', Icons.trending_up, onOpenProgress)),
          const SizedBox(width: 6),
          Expanded(child: _action('Planning', Icons.calendar_month, onQuickPlan)),
          const SizedBox(width: 6),
          Expanded(child: _action('Badges $badgeCount/${badges.length}', Icons.emoji_events, onOpenBadges)),
        ]),

      if (challenges.isNotEmpty) ...[
        const SizedBox(height: 18), CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('🎯 Défi de la semaine', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), const SizedBox(height: 8),
          ...challenges.take(2).map((ch) { final current = challengeProgress(ch); final done = current >= ch.target; return Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${done ? '✅' : '◻️'} ${ch.description}', style: TextStyle(fontWeight: FontWeight.w600, decoration: done ? TextDecoration.lineThrough : null)), const SizedBox(height: 5), progress((current / ch.target).clamp(0.0, 1.0).toDouble())])); }),
        ])),
      ],

      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 18), Text('💡 Le coach a remarqué', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 8),
        CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...suggestions.take(2).map((s) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(s.icon, size: 18, color: s.color), const SizedBox(width: 9), Expanded(child: Text(s.text, style: const TextStyle(fontSize: 13)))]))),
          if (suggestions.first.instruction != null) ...[const Divider(), Wrap(spacing: 4, children: [TextButton.icon(onPressed: () => onOrientSuggestion(suggestions.first.instruction!), icon: const Icon(Icons.event_repeat, size: 16), label: const Text('Semaine prochaine')), TextButton.icon(onPressed: () async { final i = suggestions.first.instruction; if (i != null) await onOrientSuggestionThisWeek(i); }, icon: const Icon(Icons.today, size: 16), label: const Text('Cette semaine'))])],
        ])),
      ],
    ]);
  }

  Widget _stat(BuildContext c, IconData icon, String label, String value, double ratio) => CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 18, color: Theme.of(c).colorScheme.primary), const SizedBox(width: 7), Text(label, style: const TextStyle(fontWeight: FontWeight.w700))]), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(height: 7), progress(ratio)]));
  Widget _action(String label, IconData icon, VoidCallback action) => FilledButton.tonalIcon(onPressed: action, icon: Icon(icon, size: 17), label: Text(label, overflow: TextOverflow.ellipsis));

  void _showSettings(BuildContext c) {
    showDialog<void>(context: c, builder: (dc) => SimpleDialog(title: const Text('Réglages'), children: [
      SimpleDialogOption(onPressed: () { Navigator.pop(dc); onToggleDarkMode(); }, child: Row(children: [const Icon(Icons.dark_mode), const SizedBox(width: 12), Expanded(child: Text(darkMode ? 'Mode sombre activé' : 'Mode sombre désactivé')), Switch(value: darkMode, onChanged: (_) { Navigator.pop(dc); onToggleDarkMode(); })])),
      const Divider(),
      SimpleDialogOption(onPressed: () { Navigator.pop(dc); onEditCapacity(); }, child: const Row(children: [Icon(Icons.tune), SizedBox(width: 12), Text('Mes disponibilités')])),
      SimpleDialogOption(onPressed: () { Navigator.pop(dc); onQuickProject(); }, child: const Row(children: [Icon(Icons.add_circle_outline), SizedBox(width: 12), Text('Ajouter un morceau')])),
      SimpleDialogOption(onPressed: () { Navigator.pop(dc); onExport(); }, child: const Row(children: [Icon(Icons.download_outlined), SizedBox(width: 12), Text('Exporter mes données')])),
      SimpleDialogOption(onPressed: () { Navigator.pop(dc); onImport(); }, child: const Row(children: [Icon(Icons.upload_outlined), SizedBox(width: 12), Text('Restaurer une sauvegarde')])),
      SimpleDialogOption(onPressed: () async { Navigator.pop(dc); await onResetPracticeBase(); }, child: const Row(children: [Icon(Icons.restart_alt_outlined), SizedBox(width: 12), Text('Préparer une base de test propre')])),
    ]));
  }
}

class Sessions extends StatefulWidget {
  const Sessions({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.projectById,
    required this.onOpenProject,
  });
  final List<Session> items;
  final VoidCallback onAdd;
  final void Function(Session) onEdit;
  final void Function(Session) onDelete;
  final Project? Function(String?) projectById;
  final Future<void> Function(Project) onOpenProject;

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

  String _feelingLabel(String? feeling) {
    switch (feeling) {
      case 'facile': return '😊 Facile';
      case 'correct': return '😐 Correct';
      case 'difficile': return '😓 Difficile';
      default: return '';
    }
  }

  Widget _feelingChip(BuildContext c, Session s) {
    final label = _feelingLabel(s.coachFeeling);
    if (label.isEmpty) return const SizedBox.shrink();
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.psychology_outlined, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

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

  Future<void> _showSessionDetails(BuildContext c, Session s) async {
    final p = widget.projectById(s.projectId);
    String pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';
    await showDialog<void>(
      context: c,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: [
          Icon(categoryIcon(s.type), color: categoryColor(s.type)),
          const SizedBox(width: 8),
          Expanded(child: Text(p?.name ?? 'Pratique libre')),
        ]),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.date.day.toString().padLeft(2, '0')}/${s.date.month.toString().padLeft(2, '0')}/${s.date.year} · ${s.duration} min', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (s.plannedDuration != null || s.plannedTempo != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(c).colorScheme.primaryContainer.withOpacity(.28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(c).colorScheme.primary.withOpacity(.16)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('📊 Prévu / réalisé', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  if (s.plannedDuration != null) Text('⏱️ Durée : ${s.plannedDuration} min prévue → ${s.duration} min réalisée'),
                  if (s.plannedTempo != null) Text('🎹 Tempo prévu : ${s.plannedTempo} BPM${p != null && p.currentTempo > 0 ? ' → ${p.currentTempo} BPM' : ''}'),
                ]),
              ),
            ],
            if (s.type == 'Run-through' && s.runThroughCompleted != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(c).colorScheme.secondaryContainer.withOpacity(.35),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(s.runThroughCompleted! ? Icons.check_circle_outline : Icons.stop_circle_outlined, size: 19, color: Theme.of(c).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    s.runThroughCompleted!
                        ? 'Run-through terminé : exécution complète.'
                        : 'Run-through interrompu${s.runThroughStopNote == null || s.runThroughStopNote!.trim().isEmpty ? '' : ' · ${s.runThroughStopNote}'}',
                    style: const TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600),
                  )),
                ]),
              ),
            ],
            if (s.type == 'Run-through' && (s.runThroughStartTempo != null || s.runThroughEndTempo != null)) ...[
              const SizedBox(height: 8),
              Text(
                '🎹 Tempo : ${s.runThroughStartTempo ?? '—'} BPM → ${s.runThroughEndTempo ?? '—'} BPM',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
            if (s.type == 'Run-through' && runThroughResultLabel(s, p).isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(c).colorScheme.primaryContainer.withOpacity(.45),
                ),
                child: Text(
                  runThroughResultLabel(s, p),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Chip(label: Text(s.type)),
              if (s.method != null && s.method!.isNotEmpty) Chip(label: Text(s.method!)),
              if (_feelingLabel(s.coachFeeling).isNotEmpty) Chip(label: Text(_feelingLabel(s.coachFeeling))),
              if (s.rating > 0) Chip(label: Text('★' * s.rating)),
            ]),
            if (s.coachFocus != null && s.coachFocus!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Focus travaillé', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.coachFocus!),
            ],
            if (s.coachRecommendation != null && s.coachRecommendation!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('🎯 Recommandation du coach', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.coachRecommendation!, style: const TextStyle(height: 1.35)),
            ],
            if (s.hasProgressSnapshot) ...[
              const SizedBox(height: 14),
              const Text('État du morceau avant cette séance', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Lecture / mains séparées : ${pct(s.previousReading)}'),
              Text('Mains ensemble : ${pct(s.previousHandsTogether)}'),
              Text('Mémorisation : ${pct(s.previousMemory)}'),
              Text('Interprétation : ${pct(s.previousInterpretation)}'),
            ],
            if (p != null) ...[
              const SizedBox(height: 14),
              const Text('État actuel du morceau', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Lecture / mains séparées : ${pct(p.reading)}'),
              Text('Mains ensemble : ${pct(p.handsTogether)}'),
              Text('Mémorisation : ${pct(p.memory)}'),
              Text('Interprétation : ${pct(p.interpretation)}'),
              if (p.currentTempo > 0) Text('Tempo : ${p.currentTempo} BPM${p.targetTempo > 0 ? ' / cible ${p.targetTempo} BPM' : ''}'),
            ],
            if (s.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Notes', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.notes, style: const TextStyle(height: 1.35)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer')),
          if (p != null)
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await widget.onOpenProject(p);
              },
              icon: const Icon(Icons.music_note_outlined),
              label: const Text('Voir le morceau'),
            ),
          FilledButton.icon(
            onPressed: () { Navigator.pop(dialogContext); widget.onEdit(s); },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modifier'),
          ),
        ],
      ),
    );
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
            DropdownButton<String?>(value: typeFilter, hint: const Text('Type'), items: [const DropdownMenuItem<String?>(value: null, child: Text('Tous les types')), const DropdownMenuItem<String?>(value: 'Run-through', child: Text('Run-through')), ...objectiveCategories.map((v) => DropdownMenuItem<String?>(value:v, child:Text(v)))], onChanged: (v) => setState(() => typeFilter=v)),
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
                                if (s.coachFeeling != null) _feelingChip(c, s),
                              ]),
                              if (s.coachFocus != null || s.coachRecommendation != null) ...[
                                const SizedBox(height: 4),
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Icon(Icons.auto_awesome, size: 14, color: Theme.of(c).colorScheme.primary),
                                  const SizedBox(width: 5),
                                  Expanded(child: Text(
                                    s.coachRecommendation ?? 'Focus : ${s.coachFocus}',
                                    softWrap: true,
                                    style: TextStyle(fontSize: 11, height: 1.35, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                  )),
                                ]),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 20),
                          tooltip: 'Voir le bilan',
                          onPressed: () => _showSessionDetails(c, s),
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

class _RunThroughResult {
  const _RunThroughResult({required this.completed, required this.stopNote, this.startTempo, this.endTempo});
  final bool completed;
  final String stopNote;
  final int? startTempo;
  final int? endTempo;
}

class _RunThroughResultDialog extends StatefulWidget {
  const _RunThroughResultDialog({this.initialTempo});
  final int? initialTempo;
  @override
  State<_RunThroughResultDialog> createState() => _RunThroughResultDialogState();
}

class _RunThroughResultDialogState extends State<_RunThroughResultDialog> {
  bool completed = true;
  late final TextEditingController noteCtrl;
  late final TextEditingController startTempoCtrl;
  late final TextEditingController endTempoCtrl;

  @override
  void initState() {
    super.initState();
    noteCtrl = TextEditingController();
    final t = widget.initialTempo;
    startTempoCtrl = TextEditingController(text: t == null || t <= 0 ? '' : t.toString());
    endTempoCtrl = TextEditingController(text: t == null || t <= 0 ? '' : t.toString());
  }

  @override
  void dispose() {
    noteCtrl.dispose();
    startTempoCtrl.dispose();
    endTempoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('🎹 Bilan du Run-through'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Comment s’est déroulée l’exécution ?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('✅ Terminé')),
                ButtonSegment(value: false, label: Text('⏹️ Interrompu')),
              ],
              selected: {completed},
              onSelectionChanged: (v) => setState(() => completed = v.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: startTempoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tempo départ', suffixText: 'BPM'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: endTempoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tempo réalisé', suffixText: 'BPM'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: completed ? 'Observation (facultatif)' : 'Point d’arrêt (facultatif)',
                hintText: completed ? 'Ex. quelques hésitations dans les transitions' : 'Ex. mesure 73 ou passage difficile',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _RunThroughResult(
                completed: completed,
                stopNote: noteCtrl.text,
                startTempo: int.tryParse(startTempoCtrl.text.trim()),
                endTempo: int.tryParse(endTempoCtrl.text.trim()),
              ),
            ),
            child: const Text('Enregistrer'),
          ),
        ],
      );
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
    this.initialCoachFocus,
    this.initialCoachRecommendation,
    this.initialCoachTempo,
    this.initialPlannedDuration,
    this.initialRunThroughCompleted,
    this.initialRunThroughStopNote,
    this.initialRunThroughStartTempo,
    this.initialRunThroughEndTempo,
  });
  final List<Project> projects;
  final Session? existing;
  final int? initialDuration;
  final String? initialProjectId;
  final String? initialType;
  final String? initialNotes;
  final String? initialMethod;
  final String? initialCoachFocus;
  final String? initialCoachRecommendation;
  final int? initialCoachTempo;
  final int? initialPlannedDuration;
  final bool? initialRunThroughCompleted;
  final String? initialRunThroughStopNote;
  final int? initialRunThroughStartTempo;
  final int? initialRunThroughEndTempo;
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

  Widget _sectionHeader(BuildContext c, String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(c).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .35),
              ),
            ),
          ],
        ),
      );

  Widget _coachSection(BuildContext c, int? plannedMinutes) {
    final hasCoach = widget.initialCoachFocus != null ||
        widget.initialCoachRecommendation != null ||
        widget.initialCoachTempo != null;
    if (!hasCoach) return const SizedBox.shrink();

    final recommendation = widget.initialCoachRecommendation?.trim() ?? '';
    final onSurfaceVariant = Theme.of(c).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(c).colorScheme.surfaceContainerHighest.withOpacity(.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.psychology_outlined, size: 19, color: Theme.of(c).colorScheme.primary),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text('PLAN COACH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            if (plannedMinutes != null || (widget.initialDuration != null && plannedMinutes != widget.initialDuration)) ...[
              const SizedBox(height: 7),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  if (plannedMinutes != null)
                    Text('⏱ $plannedMinutes min prévu', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.primary)),
                  if (widget.initialDuration != null && plannedMinutes != null && widget.initialDuration != plannedMinutes)
                    Text('Réel : ${widget.initialDuration} min', style: TextStyle(fontSize: 11, color: onSurfaceVariant)),
                ],
              ),
            ],
            if (widget.initialCoachFocus != null) ...[
              const SizedBox(height: 7),
              Text('🎯 Focus : ${widget.initialCoachFocus}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.25)),
            ],
            if (widget.initialCoachTempo != null && widget.initialCoachTempo! > 0) ...[
              const SizedBox(height: 4),
              Text('🎹 Tempo de référence : ${widget.initialCoachTempo} BPM', style: const TextStyle(fontSize: 11.5, height: 1.25)),
            ],
            if (recommendation.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                recommendation,
                softWrap: true,
                style: TextStyle(fontSize: 11.5, height: 1.35, color: onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final editing = widget.existing != null;
    final plannedMinutes = widget.existing?.plannedDuration ?? widget.initialPlannedDuration;
    final media = MediaQuery.of(c);
    final maxWidth = math.min(media.size.width - 24, 620.0);
    final maxHeight = math.min(media.size.height * .82, 720.0);
    final flatTheme = Theme.of(c).copyWith(
      inputDecorationTheme: Theme.of(c).inputDecorationTheme.copyWith(
        border: const UnderlineInputBorder(),
        enabledBorder: const UnderlineInputBorder(),
        focusedBorder: const UnderlineInputBorder(),
        errorBorder: const UnderlineInputBorder(),
        focusedErrorBorder: const UnderlineInputBorder(),
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.only(left: 0, right: 0, top: 10, bottom: 8),
      ),
    );

    return Theme(
      data: flatTheme,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
        contentPadding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
        actionsPadding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
        title: Row(
          children: [
            Icon(editing ? Icons.edit_note_outlined : Icons.add_task_outlined, color: Theme.of(c).colorScheme.primary),
            const SizedBox(width: 9),
            Expanded(child: Text(editing ? 'Modifier la session' : 'Nouvelle session')),
          ],
        ),
        content: SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader(c, 'SÉANCE', Icons.music_note_outlined),
                DropdownButtonFormField<Project?>(
                  isExpanded: true,
                  value: project,
                  decoration: const InputDecoration(labelText: 'Morceau'),
                  items: projectItems(widget.projects),
                  onChanged: (v) => setState(() => project = v),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type de travail'),
                  items: ['Run-through', ...objectiveCategories]
                      .map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: method,
                  decoration: const InputDecoration(labelText: 'Application / méthode'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Aucune')),
                    ...learningMethods.map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => method = v),
                ),
                const SizedBox(height: 5),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée (minutes)', suffixText: 'min'),
                  onChanged: (v) => setState(() => duration = int.tryParse(v) ?? duration),
                ),

                _coachSection(c, plannedMinutes),

                _sectionHeader(c, 'NOTES ET RESSENTI', Icons.edit_note_outlined),
                TextField(
                  controller: notesCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Ce qui a été travaillé, difficultés, remarques…',
                    alignLabelWithHint: true,
                  ),
                ),

                _sectionHeader(c, 'ÉVALUATION', Icons.star_outline),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: rating,
                  decoration: const InputDecoration(labelText: 'Note de séance'),
                  items: List.generate(
                    5,
                    (i) => DropdownMenuItem(value: i + 1, child: Text('★' * (i + 1))),
                  ),
                  onChanged: (v) => setState(() => rating = v ?? rating),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton.icon(
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
                previousReading: widget.existing?.previousReading,
                previousHandsTogether: widget.existing?.previousHandsTogether,
                previousMemory: widget.existing?.previousMemory,
                previousInterpretation: widget.existing?.previousInterpretation,
                previousTempo: widget.existing?.previousTempo,
                newTempo: widget.existing?.newTempo,
                newReading: widget.existing?.newReading,
                newHandsTogether: widget.existing?.newHandsTogether,
                newMemory: widget.existing?.newMemory,
                newInterpretation: widget.existing?.newInterpretation,
                coachFeeling: widget.existing?.coachFeeling,
                coachFocus: widget.existing?.coachFocus ?? widget.initialCoachFocus,
                coachRecommendation: widget.existing?.coachRecommendation ?? widget.initialCoachRecommendation,
                plannedDuration: widget.existing?.plannedDuration ?? widget.initialPlannedDuration,
                plannedTempo: widget.existing?.plannedTempo ?? widget.initialCoachTempo,
                runThroughCompleted: widget.existing?.runThroughCompleted ?? widget.initialRunThroughCompleted,
                runThroughStopNote: widget.existing?.runThroughStopNote ?? widget.initialRunThroughStopNote,
                runThroughStartTempo: widget.existing?.runThroughStartTempo ?? widget.initialRunThroughStartTempo,
                runThroughEndTempo: widget.existing?.runThroughEndTempo ?? widget.initialRunThroughEndTempo,
              ),
            ),
            icon: const Icon(Icons.check, size: 18),
            label: Text(editing ? 'Enregistrer' : 'Créer la session'),
          ),
        ],
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// Projets
// ---------------------------------------------------------------------------

Color _statusSoftColor(BuildContext c, String status) {
  final s = Theme.of(c).colorScheme;
  switch (status) {
    case 'À découvrir': return s.secondaryContainer.withOpacity(.62);
    case 'En cours de déchiffrage':
    case 'En cours de déchiffrement': return s.tertiaryContainer.withOpacity(.62);
    case 'En mémorisation': return s.primaryContainer.withOpacity(.62);
    case 'Acquis': return Colors.green.withOpacity(.12);
    case 'Répertoire d’entretien': return Colors.orange.withOpacity(.13);
    default: return s.surfaceContainerHighest;
  }
}

Color _statusStrongColor(BuildContext c, String status) {
  final s = Theme.of(c).colorScheme;
  switch (status) {
    case 'À découvrir': return s.onSecondaryContainer;
    case 'En cours de déchiffrage':
    case 'En cours de déchiffrement': return s.onTertiaryContainer;
    case 'En mémorisation': return s.primary;
    case 'Acquis': return Colors.green.shade700;
    case 'Répertoire d’entretien': return Colors.orange.shade800;
    default: return s.onSurfaceVariant;
  }
}

Widget _miniProgress(String label, double value) => Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label ${(value * 100).round()}%', style: const TextStyle(fontSize: 11)),
      avatar: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(value: value, strokeWidth: 2)),
    );

class Projects extends StatefulWidget {
  const Projects({super.key, required this.items, required this.sessions, required this.onAdd, required this.onEdit, required this.onDelete, required this.onDuplicate});
  final List<Project> items;
  final List<Session> sessions;
  final VoidCallback onAdd;
  final void Function(Project) onEdit;
  final void Function(Project) onDelete;
  final void Function(Project) onDuplicate;

  @override
  State<Projects> createState() => _ProjectsState();
}

class _ProjectsState extends State<Projects> {
  String? filterStatus;
  String sortMode = 'recent';

  DateTime _lastModifiedFor(Project p) {
    if (p.lastModified.millisecondsSinceEpoch > 0) return p.lastModified;
    final pieceSessions = widget.sessions.where((s) => s.projectId == p.id).toList();
    if (pieceSessions.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return pieceSessions.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  @override
  Widget build(BuildContext c) {
    final visible = filterStatus == null
        ? [...widget.items]
        : widget.items.where((p) => p.effectiveStatus == filterStatus).toList();
    final sorted = [...visible]..sort((a, b) {
      switch (sortMode) {
        case 'name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'status':
          final statusCompare = projectStatuses.indexOf(a.effectiveStatus).compareTo(projectStatuses.indexOf(b.effectiveStatus));
          if (statusCompare != 0) return statusCompare;
          return (b.priority ? 1 : 0) - (a.priority ? 1 : 0);
        case 'recent':
        default:
          return _lastModifiedFor(b).compareTo(_lastModifiedFor(a));
      }
    });
    return Column(
      children: [
        AppBar(title: Text('Morceaux · ${widget.items.length}'), actions: [IconButton(onPressed: widget.onAdd, icon: const Icon(Icons.add))]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
                isExpanded: true,
                value: filterStatus,
                decoration: const InputDecoration(
                  labelText: 'Filtrer',
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: sortMode,
                decoration: const InputDecoration(
                  labelText: 'Trier',
                  prefixIcon: Icon(Icons.sort),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'recent', child: Text('Dernière modification')),
                  DropdownMenuItem(value: 'status', child: Text('Statut')),
                  DropdownMenuItem(value: 'name', child: Text('Nom')),
                ],
                onChanged: (v) => setState(() => sortMode = v ?? 'recent'),
              ),
            ],
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
                    final pieceRunThroughs = widget.sessions.where((s) => s.projectId == p.id && s.type == 'Run-through').toList();
                    final completedPieceRuns = pieceRunThroughs.where((s) => s.runThroughCompleted == true).toList();
                    final measuredPieceTempos = completedPieceRuns
                        .map((s) => s.runThroughEndTempo ?? 0)
                        .where((tempo) => tempo > 0)
                        .toList();
                    final bestPieceRunTempo = measuredPieceTempos.isEmpty ? null : measuredPieceTempos.reduce(math.max);
                    final pieceRunMastery = (completedPieceRuns.isNotEmpty || p.currentTempo > 0)
                        ? pieceMasteryScore(p, pieceRunThroughs)
                        : null;
                    final runScore = completedPieceRuns.isNotEmpty ? runThroughMasteryScore(p, pieceRunThroughs) : 0.0;
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
                                  icon: const Icon(Icons.copy_outlined, size: 20),
                                  tooltip: 'Dupliquer',
                                  onPressed: () => widget.onDuplicate(p),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  tooltip: 'Supprimer',
                                  onPressed: () async {
                                    if (await confirmDelete(c, 'ce morceau')) widget.onDelete(p);
                                  },
                                ),
                              ]),
                              const SizedBox(height: 5),
                              Row(children: [
                                Icon(Icons.update_outlined, size: 14, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    'Dernière modification : ${_formatProjectDateTime(_lastModifiedFor(p))}',
                                    style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: _statusSoftColor(c, p.effectiveStatus),
                                  ),
                                  child: Text('${projectStatusEmoji(p.effectiveStatus)}  ${p.effectiveStatus}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _statusStrongColor(c, p.effectiveStatus))),
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
                              if (pieceRunMastery != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Theme.of(c).colorScheme.primaryContainer.withOpacity(.42),
                                    border: Border.all(color: Theme.of(c).colorScheme.primary.withOpacity(.18)),
                                  ),
                                  child: Row(children: [
                                    Icon(Icons.insights_outlined, size: 18, color: Theme.of(c).colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('🎯 Maîtrise Run-through', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Theme.of(c).colorScheme.onSurface)),
                                      const SizedBox(height: 3),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(5),
                                        child: LinearProgressIndicator(value: pieceRunMastery / 100, minHeight: 6),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${pieceRunMastery.round()} % · ${masteryLabel(pieceRunMastery)} · ${completedPieceRuns.length} run-through${completedPieceRuns.length > 1 ? 's' : ''} · ${p.targetTempo > 0 ? 'cible ${p.targetTempo} BPM' : 'tempo en suivi'}',
                                        style: TextStyle(fontSize: 10, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                      ),
                                    ])),
                                    const SizedBox(width: 10),
                                    Text('${pieceRunMastery.round()} %', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Theme.of(c).colorScheme.primary)),
                                  ]),
                                ),
                              ],
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
      Container(width: 34, height: 34, alignment: Alignment.center,
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



class _ProjectCoachDashboard extends StatelessWidget {
  const _ProjectCoachDashboard({required this.project, required this.sessions, required this.scheduledCoachSessions, required this.onScheduleCoachSession});
  final Project project;
  final List<Session> sessions;
  final List<PlanItem> scheduledCoachSessions;
  final Future<void> Function(PlanItem) onScheduleCoachSession;

  String _feeling(String? value) {
    switch (value) {
      case 'facile': return '😊 Facile';
      case 'correct': return '😐 Correct';
      case 'difficile': return '😓 Difficile';
      default: return '—';
    }
  }

  double _weakestStage() {
    final values = [project.reading, project.handsTogether, project.memory, project.interpretation];
    return values.reduce(math.min);
  }

  String _weakestLabel() {
    final values = <String, double>{
      'Lecture': project.reading,
      'Mains ensemble': project.handsTogether,
      'Mémorisation': project.memory,
      'Interprétation': project.interpretation,
    };
    return values.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  double? _after(Session s, int stage) {
    final direct = [s.newReading, s.newHandsTogether, s.newMemory, s.newInterpretation][stage];
    if (direct != null) return direct;
    final index = sessions.indexOf(s);
    if (index >= 0 && index + 1 < sessions.length) {
      final next = sessions[index + 1];
      return [next.previousReading, next.previousHandsTogether, next.previousMemory, next.previousInterpretation][stage];
    }
    return [project.reading, project.handsTogether, project.memory, project.interpretation][stage];
  }

  double? _before(Session s, int stage) {
    return [s.previousReading, s.previousHandsTogether, s.previousMemory, s.previousInterpretation][stage];
  }

  double? _plannedDurationAdherence() {
    final recent = [...sessions.where((s) => s.plannedDuration != null && s.plannedDuration! > 0)]
      ..sort((a, b) => b.date.compareTo(a.date));
    final selected = recent.take(3).toList();
    if (selected.isEmpty) return null;
    final ratios = selected.map((s) => s.duration / s.plannedDuration!).toList();
    return ratios.fold<double>(0, (a, b) => a + b) / ratios.length;
  }

  String _durationAdjustmentHint() {
    final adherence = _plannedDurationAdherence();
    if (adherence == null) return '';
    final lastFeeling = sessions.isEmpty ? null : ([...sessions]..sort((a, b) => b.date.compareTo(a.date))).first.coachFeeling;
    if (adherence < .80) return 'Les dernières séances ont été plus courtes que prévu : le coach allège légèrement la prochaine séance.';
    if (adherence > 1.20 && lastFeeling != 'difficile') return 'Tu dépasses régulièrement le temps prévu sans signal de difficulté : le coach peut augmenter légèrement la charge.';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ordered = [...sessions]..sort((a, b) => a.date.compareTo(b.date));
    final recent = ordered.length >= 2 ? ordered.sublist(ordered.length - 2) : ordered;
    final last = ordered.isNotEmpty ? ordered.last : null;
    final stageNames = ['Lecture', 'Mains ensemble', 'Mémorisation', 'Interprétation'];
    final deltas = <MapEntry<String, double>>[];
    if (last != null) {
      for (var i = 0; i < 4; i++) {
        final before = _before(last, i);
        final after = _after(last, i);
        if (before != null && after != null) deltas.add(MapEntry(stageNames[i], after - before));
      }
    }
    final improved = deltas.where((e) => e.value >= 0.05).toList();
    final stagnant = deltas.where((e) => e.value.abs() < 0.05).toList();
    final difficult = recent.where((s) => s.coachFeeling == 'difficile').length;
    final tempoGap = project.targetTempo > 0 && project.currentTempo > 0 ? project.targetTempo - project.currentTempo : 0;
    final completedRuns = sessions.where((s) => s.type == 'Run-through' && s.runThroughCompleted == true).toList();
    final bestRunTempo = completedRuns.fold<int>(0, (best, s) {
      final tempo = s.runThroughEndTempo ?? 0;
      return tempo > best ? tempo : best;
    });
    final runMastery = completedRuns.isEmpty ? null : runThroughMasteryScore(project, sessions);
    final pieceMastery = pieceMasteryScore(project, sessions);
    // V118 : indicateur de maîtrise réellement composite, distinct du simple % d'étapes.
    final masteryDelta = pieceMastery - ((project.progress * 100).clamp(0.0, 100.0));
    String masteryAdvice;
    if (pieceMastery >= 85 && (project.targetTempo <= 0 || project.currentTempo >= project.targetTempo * .90)) {
      masteryAdvice = 'Le morceau approche une maîtrise exploitable : privilégie maintenant la régularité et le run-through.';
    } else if (masteryDelta < -10) {
      masteryAdvice = 'La maîtrise pratique reste en retrait par rapport à l’avancement affiché : consolide les points qui résistent.';
    } else if (project.targetTempo > 0 && project.currentTempo > 0 && project.currentTempo < project.targetTempo * .80) {
      masteryAdvice = 'La progression est engagée, mais le tempo reste le principal frein à une maîtrise réelle.';
    } else {
      masteryAdvice = 'La maîtrise progresse : continue à rapprocher les étapes, le tempo et la continuité.';
    }

    String progressText;
    final masteryColor = scheme.primary;

    if (improved.isNotEmpty) {
      progressText = improved.map((e) => '${e.key} +${(e.value * 100).round()}%').join(' · ');
    } else if (sessions.isEmpty) {
      progressText = 'Pas encore assez de séances pour mesurer la progression.';
    } else {
      progressText = 'Les étapes évoluent peu sur la dernière séance.';
    }
    String stableText;
    if (stagnant.isNotEmpty) {
      stableText = stagnant.map((e) => e.key).join(' · ');
    } else {
      stableText = 'Aucune étape clairement stagnante sur la dernière séance.';
    }
    String nextText;
    if (last?.type == 'Run-through' && last?.runThroughCompleted == false) {
      final stop = last?.runThroughStopNote?.trim();
      nextText = stop != null && stop.isNotEmpty
          ? 'Run-through interrompu ($stop) : travaille ce point avant de refaire une exécution complète.'
          : 'Run-through interrompu : consolide le point difficile avant de refaire une exécution complète.';
    } else if (last?.type == 'Run-through' && last?.runThroughCompleted == true) {
      nextText = last?.runThroughEndTempo != null && project.targetTempo > 0 && last!.runThroughEndTempo! < project.targetTempo
          ? 'Run-through terminé : la continuité est acquise ; consolide encore la régularité autour de ${last.runThroughEndTempo} BPM avant de viser ${project.targetTempo} BPM.'
          : 'Run-through terminé : consolide la continuité et vise une exécution de plus en plus régulière.';
    } else if (difficult >= 2) {
      nextText = 'Deux séances difficiles récemment : consolide ${_weakestLabel().toLowerCase()} avant d’ajouter de la vitesse.';
    } else if (project.workFocus != 'Automatique') {
      nextText = 'Travail prioritaire : ${project.workFocus.toLowerCase()}, avec une intensité ${project.workIntensity.toLowerCase()}.';
    } else if (tempoGap > 0) {
      nextText = 'Prochaine priorité : ${_weakestLabel().toLowerCase()}, puis rapproche progressivement le tempo de la cible (${project.targetTempo} BPM).';
    } else {
      nextText = 'Prochaine priorité : ${_weakestLabel().toLowerCase()} (${(_weakestStage() * 100).round()}%).';
    }
    if (last?.coachFeeling == 'difficile' && difficult < 2) {
      nextText = 'Dernière séance difficile : ${nextText[0].toLowerCase()}${nextText.substring(1)}';
    }
    final masteryPercent = pieceMastery.round();
    final runPercent = runMastery?.round();

    // V118 : carte de maîtrise synthétique, lisible en un seul coup d'œil.
    final masteryPanel = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withOpacity(.16)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 44, height: 44, child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(value: masteryPercent / 100, strokeWidth: 4),
          Text('$masteryPercent%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        ])),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('MAÎTRISE DU MORCEAU · ${masteryLabel(pieceMastery)}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: masteryColor, letterSpacing: .5)),
          const SizedBox(height: 4),
          Text(masteryAdvice, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, height: 1.28)),
          if (runPercent != null) ...[
            const SizedBox(height: 4),
            Text('Run-through : $runPercent %', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
          ],
        ])),
      ]),
    );

    // Recommandation immédiatement actionnable pour la prochaine séance.
    final adherence = _plannedDurationAdherence();
    var recommendedMinutes = last?.type == 'Run-through' && last?.runThroughCompleted == false
        ? 15
        : (last?.coachFeeling == 'difficile' ? 15 : (last?.coachFeeling == 'facile' ? 25 : 20));
    if (adherence != null) {
      if (adherence < .80) {
        recommendedMinutes -= 5;
      } else if (adherence > 1.20 && last?.coachFeeling != 'difficile') {
        recommendedMinutes += 5;
      }
    }
    recommendedMinutes = recommendedMinutes.clamp(10, 30);
    final recommendedFocus = project.workFocus != 'Automatique'
        ? project.workFocus
        : _weakestLabel();
    var recommendedTempo = project.currentTempo > 0
        ? project.currentTempo
        : null;
    final tempoSessions = [...sessions]..sort((a, b) => b.date.compareTo(a.date));
    final tempoSamples = tempoSessions
        .where((s) => s.plannedTempo != null && (s.newTempo != null || s.runThroughEndTempo != null))
        .take(3)
        .toList();
    if (recommendedTempo != null) {
      if (last?.coachFeeling == 'difficile' || tempoSamples.where((s) => (s.newTempo ?? s.runThroughEndTempo)! < s.plannedTempo!).length >= 2) {
        recommendedTempo = math.max(1, recommendedTempo! - 5);
      } else if (last?.coachFeeling == 'facile' && tempoSamples.where((s) => (s.newTempo ?? s.runThroughEndTempo)! >= s.plannedTempo! + 3).length >= 2) {
        recommendedTempo = recommendedTempo! + 3;
      }
    }
    final goalHint = project.goal.trim().isNotEmpty ? ' · Objectif : ${project.goal.trim()}' : '';
    final concretePlan = recommendedTempo != null
        ? '$recommendedMinutes min · $recommendedFocus · ${recommendedTempo} BPM$goalHint'
        : '$recommendedMinutes min · $recommendedFocus$goalHint';

    // Synthèse dédiée des run-throughs : cet indicateur mesure la capacité à jouer
    // le morceau en continu, distinctement des séances de travail ciblé.
    final runThroughs = [...sessions.where((s) => s.type == 'Run-through')]
      ..sort((a, b) => b.date.compareTo(a.date));
    final completedRunThroughs = runThroughs.where((s) => s.runThroughCompleted == true).toList();
    final latestRunThrough = runThroughs.isNotEmpty ? runThroughs.first : null;
    final measuredCompletedRuns = completedRunThroughs
        .where((s) => (s.runThroughEndTempo ?? 0) > 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final measuredTempos = measuredCompletedRuns
        .map((s) => s.runThroughEndTempo!)
        .toList();
    final bestMeasuredRunTempo = measuredTempos.isEmpty ? null : measuredTempos.reduce(math.max);
    final targetTempo = project.targetTempo > 0 ? project.targetTempo : null;
    final runTempoRatio = bestMeasuredRunTempo != null && targetTempo != null ? bestMeasuredRunTempo / targetTempo : null;
    final latestMeasuredRun = measuredCompletedRuns.isNotEmpty ? measuredCompletedRuns.first : null;
    final previousMeasuredRun = measuredCompletedRuns.length > 1 ? measuredCompletedRuns[1] : null;
    final latestRunEndTempo = latestMeasuredRun?.runThroughEndTempo;
    final previousRunEndTempo = previousMeasuredRun?.runThroughEndTempo;
    final runTempoDelta = latestRunEndTempo != null && previousRunEndTempo != null
        ? latestRunEndTempo - previousRunEndTempo
        : null;
    final runTempoTargetPercent = latestRunEndTempo != null && targetTempo != null
        ? ((latestRunEndTempo / targetTempo).clamp(0.0, 1.0) * 100).round()
        : null;
    String runThroughCoachAdvice;
    if (latestMeasuredRun == null) {
      runThroughCoachAdvice = 'Enregistre un tempo de fin lors du prochain Run-through pour suivre la progression.';
    } else if (latestRunEndTempo != null && targetTempo != null && latestRunEndTempo >= targetTempo) {
      runThroughCoachAdvice = 'Tempo cible atteint : privilégie maintenant la régularité et la qualité d’exécution.';
    } else if (runTempoDelta != null && runTempoDelta >= 5) {
      runThroughCoachAdvice = 'La progression est nette (+$runTempoDelta BPM) : consolide ce tempo avant d’accélérer davantage.';
    } else if (runTempoDelta != null && runTempoDelta <= -5) {
      runThroughCoachAdvice = 'Le tempo a baissé ($runTempoDelta BPM) : reprends quelques passages ciblés avant le prochain Run-through.';
    } else if (latestRunEndTempo != null && targetTempo != null && latestRunEndTempo < targetTempo * .90) {
      runThroughCoachAdvice = 'Encore sous 90 % de la cible : travaille d’abord la continuité et les passages fragiles.';
    } else {
      runThroughCoachAdvice = 'Progression stable : garde ce tempo et cherche surtout une exécution régulière.';
    }

    String concreteWhy;
    if (adherence != null && adherence < .80) {
      concreteWhy = 'Les dernières séances étaient plus courtes que prévu : charge légèrement réduite.';
    } else if (adherence != null && adherence > 1.20 && last?.coachFeeling != 'difficile') {
      concreteWhy = 'Tu dépasses régulièrement le temps prévu sans difficulté signalée : charge légèrement augmentée.';
    } else if (last?.coachFeeling == 'difficile') {
      concreteWhy = 'Charge réduite pour consolider sans forcer.';
    } else if (last?.coachFeeling == 'facile') {
      concreteWhy = 'Le dernier travail était facile : tu peux légèrement augmenter la charge.';
    } else {
      concreteWhy = 'Une séance courte et ciblée pour faire avancer le point le plus utile.';
    }

    // Synthèse explicite : quoi travailler, combien de temps, à quel tempo et pourquoi.
    final coachAction = last?.type == 'Run-through' && last?.runThroughCompleted == false
        ? ((last?.runThroughStopNote?.trim().isNotEmpty ?? false)
            ? 'Reprendre le point d’arrêt : ${last!.runThroughStopNote!.trim()}'
            : 'Reprendre le point fragile avant une nouvelle exécution complète')
        : 'Travailler ${recommendedFocus.toLowerCase()}';
    final coachTempo = recommendedTempo != null
        ? '${recommendedTempo} BPM'
        : 'tempo libre / à définir';
    final coachWhy = last?.type == 'Run-through' && last?.runThroughCompleted == true && last?.runThroughEndTempo != null
        ? 'Dernier Run-through terminé à ${last!.runThroughEndTempo} BPM : consolider la continuité avant d’accélérer.'
        : concreteWhy;

    return Padding(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.psychology_outlined, size: 19, color: scheme.primary),
            const SizedBox(width: 7),
            const Expanded(child: Text('Analyse & conseil du morceau', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            if (last != null) Text(_feeling(last.coachFeeling), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 9),
          _CoachInsightTile(icon: Icons.trending_up, title: 'Ce qui progresse', text: progressText, color: scheme.primary),
          const SizedBox(height: 8),
          masteryPanel,
          const SizedBox(height: 7),
          _CoachInsightTile(icon: Icons.pause_circle_outline, title: 'Ce qui stagne', text: stableText, color: scheme.tertiary),
          const SizedBox(height: 7),
          _CoachInsightTile(icon: Icons.flag_outlined, title: 'À travailler maintenant', text: nextText, color: scheme.secondary),
          if (runThroughs.isNotEmpty) ...[
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.play_circle_outline, size: 18, color: scheme.secondary),
                  const SizedBox(width: 7),
                  const Expanded(child: Text('RUN-THROUGH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .4)),),
                  Text('${completedRunThroughs.length}/${runThroughs.where((s) => s.runThroughCompleted != null).length} renseignés', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: scheme.secondary)),
                ]),
                const SizedBox(height: 5),
                Wrap(spacing: 8, runSpacing: 5, children: [
                  if (latestRunThrough != null)
                    Chip(avatar: const Icon(Icons.history, size: 13), label: Text(
                      latestRunThrough.runThroughCompleted == true ? 'Dernier : ✅ terminé' : (latestRunThrough.runThroughCompleted == false ? 'Dernier : ⏹️ interrompu' : 'Dernier : 🕘 ancien'),
                      style: const TextStyle(fontSize: 10),
                    ), visualDensity: VisualDensity.compact),
                  if (bestMeasuredRunTempo != null)
                    Chip(avatar: const Icon(Icons.speed_outlined, size: 13), label: Text(
                      'Meilleur : $bestMeasuredRunTempo BPM${targetTempo != null ? ' / $targetTempo' : ''}',
                      style: const TextStyle(fontSize: 10),
                    ), visualDensity: VisualDensity.compact),
                  if (runTempoRatio != null)
                    Chip(avatar: const Icon(Icons.track_changes, size: 13), label: Text(
                      '${(runTempoRatio * 100).round()} % de la cible (meilleur)',
                      style: const TextStyle(fontSize: 10),
                    ), visualDensity: VisualDensity.compact),
                ]),
                if (latestMeasuredRun != null) ...[
                  const SizedBox(height: 7),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surface.withOpacity(.48),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.show_chart, size: 18, color: scheme.primary),
                      const SizedBox(width: 7),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          'ÉVOLUTION DU TEMPO',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: scheme.primary, letterSpacing: .35),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          latestRunEndTempo != null && previousRunEndTempo != null
                              ? '${previousRunEndTempo} → ${latestRunEndTempo} BPM${runTempoDelta! >= 0 ? ' · +$runTempoDelta' : ' · $runTempoDelta'} BPM depuis le run précédent'
                              : '${latestRunEndTempo} BPM · premier Run-through mesuré',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                        if (runTempoTargetPercent != null) ...[
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(value: runTempoTargetPercent / 100, minHeight: 5),
                          ),
                          const SizedBox(height: 3),
                          Text('$runTempoTargetPercent % de la cible sur le dernier run', style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
                        ],
                        const SizedBox(height: 5),
                        Text('💡 $runThroughCoachAdvice', style: TextStyle(fontSize: 9.8, color: scheme.onSurfaceVariant, height: 1.25)),
                      ])),
                    ]),
                  ),
                ],
                if (measuredCompletedRuns.length > 1) ...[
                  const SizedBox(height: 7),
                  Text('Historique récent', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: scheme.onSurface)),
                  const SizedBox(height: 4),
                  ...measuredCompletedRuns.take(4).map((s) {
                    final idx = measuredCompletedRuns.indexOf(s);
                    final previous = idx + 1 < measuredCompletedRuns.length ? measuredCompletedRuns[idx + 1].runThroughEndTempo : null;
                    final delta = previous != null && s.runThroughEndTempo != null ? s.runThroughEndTempo! - previous : null;
                    final dateLabel = '${s.date.day.toString().padLeft(2, '0')}/${s.date.month.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        SizedBox(width: 42, child: Text(dateLabel, style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant))),
                        Expanded(child: Text('${s.runThroughStartTempo ?? '—'} → ${s.runThroughEndTempo} BPM', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
                        if (delta != null)
                          Text('${delta >= 0 ? '+' : ''}$delta', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: delta >= 0 ? scheme.primary : scheme.error))
                        else
                          const SizedBox(width: 22),
                      ]),
                    );
                  }),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withOpacity(.45),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: scheme.primary.withOpacity(.18)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.play_circle_outline, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PROCHAINE SÉANCE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: scheme.primary, letterSpacing: .4)),
                const SizedBox(height: 3),
                Text(concretePlan, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface.withOpacity(.5),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: scheme.outlineVariant.withOpacity(.7)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.flag_outlined, size: 16, color: scheme.secondary),
                      const SizedBox(width: 7),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('QUOI', style: TextStyle(fontSize: 8.8, fontWeight: FontWeight.w900, color: scheme.secondary, letterSpacing: .35)),
                        const SizedBox(height: 1),
                        Text(coachAction, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.2)),
                      ])),
                    ]),
                    const SizedBox(height: 6),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.timer_outlined, size: 16, color: scheme.primary),
                      const SizedBox(width: 7),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('COMBIEN / TEMPO', style: TextStyle(fontSize: 8.8, fontWeight: FontWeight.w900, color: scheme.primary, letterSpacing: .35)),
                        const SizedBox(height: 1),
                        Text('$recommendedMinutes min · $coachTempo', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.2)),
                      ])),
                    ]),
                    const SizedBox(height: 6),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: scheme.tertiary),
                      const SizedBox(width: 7),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('POURQUOI', style: TextStyle(fontSize: 8.8, fontWeight: FontWeight.w900, color: scheme.tertiary, letterSpacing: .35)),
                        const SizedBox(height: 1),
                        Text(coachWhy, style: TextStyle(fontSize: 10.2, color: scheme.onSurfaceVariant, height: 1.22)),
                      ])),
                    ]),
                  ]),
                ),
                if (_durationAdjustmentHint().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('🧠 ${_durationAdjustmentHint()}', style: TextStyle(fontSize: 10.2, color: scheme.onSurfaceVariant, height: 1.25)),
                ],
                const SizedBox(height: 8),
                if (scheduledCoachSessions.isNotEmpty)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_circle, size: 18, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Présente dans le planning — ${scheduledCoachSessions.first.date.day}/${scheduledCoachSessions.first.date.month} · ${scheduledCoachSessions.first.duration} min. Le coach ajuste directement le planning à partir de tes séances.',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary, height: 1.3),
                      ),
                    ),
                  ])
                else
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.sync_alt_outlined, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Le coach ne crée pas une deuxième séance ici : ses ajustements apparaissent directement dans le planning.',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.3),
                      ),
                    ),
                  ])
              ])),
            ]),
          ),
          if (sessions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 5, children: [
              Chip(avatar: const Icon(Icons.event_note_outlined, size: 14), label: Text('${sessions.length} séance${sessions.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
              if (sessions.any((s) => s.type == 'Run-through'))
                Chip(avatar: const Icon(Icons.play_circle_outline, size: 14), label: Text('${sessions.where((s) => s.type == 'Run-through' && s.runThroughCompleted == true).length}/${sessions.where((s) => s.type == 'Run-through').length} run-through terminé${sessions.where((s) => s.type == 'Run-through').length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
              if (last != null) Chip(avatar: const Icon(Icons.timer_outlined, size: 14), label: Text('${last.duration} min', style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
              if (project.currentTempo > 0) Chip(avatar: const Icon(Icons.speed_outlined, size: 14), label: Text('${project.currentTempo} BPM', style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
            ]),
            if (runMastery != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withOpacity(.28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(children: [
                  Icon(Icons.insights_outlined, size: 18, color: scheme.primary),
                  const SizedBox(width: 7),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('MAÎTRISE EN RUN-THROUGH', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('$runMastery% de la cible tempo · meilleur run-through ${bestRunTempo} BPM', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ])),
                  Text('$runMastery%', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: scheme.primary)),
                ]),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

class _CoachInsightTile extends StatelessWidget {
  const _CoachInsightTile({required this.icon, required this.title, required this.text, required this.color});
  final IconData icon;
  final String title;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: scheme.onSurface)),
          const SizedBox(height: 2),
          Text(text, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, height: 1.25)),
        ])),
      ]),
    );
  }
}

class _ProjectEvolutionSection extends StatefulWidget {
  const _ProjectEvolutionSection({required this.project, required this.sessions});
  final Project project;
  final List<Session> sessions;

  @override
  State<_ProjectEvolutionSection> createState() => _ProjectEvolutionSectionState();
}

class _ProjectEvolutionSectionState extends State<_ProjectEvolutionSection> {
  int? selectedIndex;

  String _feelingLabel(String? value) {
    switch (value) {
      case 'facile': return '😊 Facile';
      case 'difficile': return '😓 Difficile';
      case 'correct': return '😐 Correct';
      default: return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordered = [...widget.sessions]..sort((a, b) => a.date.compareTo(b.date));
    final hasStageData = ordered.any((s) => s.newReading != null || s.newHandsTogether != null || s.newMemory != null || s.newInterpretation != null || s.hasProgressSnapshot);
    final hasTempo = ordered.any((s) => (s.newTempo ?? s.previousTempo ?? 0) > 0) || widget.project.currentTempo > 0;
    final feelings = ordered.where((s) => s.coachFeeling != null).toList();
    final selected = selectedIndex != null && selectedIndex! < ordered.length ? ordered[selectedIndex!] : null;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(.55)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.show_chart, size: 18, color: scheme.primary),
            const SizedBox(width: 7),
            const Expanded(child: Text('Évolution du morceau', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            Text('${ordered.length} séances', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          const SizedBox(height: 4),
          const Text('Clique sur un point pour afficher le détail de la séance.', style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 9),
          if (hasStageData) ...[
            const Text('4 étapes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            SizedBox(
              height: 150,
              child: _StageEvolutionChart(
                sessions: ordered,
                project: widget.project,
                selectedIndex: selectedIndex,
                onSelected: (i) => setState(() => selectedIndex = i),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 10, runSpacing: 4, children: [
              _LegendDot(label: 'Lecture', color: scheme.primary),
              _LegendDot(label: 'Mains ensemble', color: scheme.secondary),
              _LegendDot(label: 'Mémorisation', color: scheme.tertiary),
              _LegendDot(label: 'Interprétation', color: scheme.error),
            ]),
          ],
          if (hasTempo) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Text('Tempo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (widget.project.targetTempo > 0) Text('cible ${widget.project.targetTempo} BPM', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
            const SizedBox(height: 4),
            SizedBox(
              height: 105,
              child: _TempoEvolutionChart(
                sessions: ordered,
                project: widget.project,
                targetTempo: widget.project.targetTempo,
                selectedIndex: selectedIndex,
                onSelected: (i) => setState(() => selectedIndex = i),
              ),
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.event_note_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    '${selected.date.day.toString().padLeft(2, '0')}/${selected.date.month.toString().padLeft(2, '0')}/${selected.date.year}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                  )),
                  Text('${selected.duration} min', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                ]),
                const SizedBox(height: 5),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  Text('Ressenti : ${_feelingLabel(selected.coachFeeling)}', style: const TextStyle(fontSize: 10)),
                  Text('Note : ${selected.rating}/5', style: const TextStyle(fontSize: 10)),
                  if ((selected.newTempo ?? 0) > 0) Text('${selected.newTempo} BPM', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
                if (selected.coachFocus != null || selected.coachRecommendation != null) ...[
                  const SizedBox(height: 4),
                  if (selected.coachFocus != null) Text('Focus : ${selected.coachFocus}', style: const TextStyle(fontSize: 10)),
                  if (selected.coachRecommendation != null) Text('Coach : ${selected.coachRecommendation}', style: const TextStyle(fontSize: 10)),
                ],
              ]),
            ),
          ],
          if (feelings.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Ressenti séance après séance', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: feelings.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final s = feelings[i];
                  final originalIndex = ordered.indexOf(s);
                  final emoji = s.coachFeeling == 'facile' ? '😊' : s.coachFeeling == 'difficile' ? '😓' : '😐';
                  final isSelected = originalIndex == selectedIndex;
                  return GestureDetector(
                    onTap: () => setState(() => selectedIndex = originalIndex),
                    child: Tooltip(
                      message: '${s.date.day}/${s.date.month}/${s.date.year} • ${s.duration} min • ${_feelingLabel(s.coachFeeling)}',
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? scheme.primaryContainer : null,
                          border: Border.all(color: isSelected ? scheme.primary : Theme.of(context).dividerColor, width: isSelected ? 2 : 1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 19)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ]),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
  ]);
}

class _StageEvolutionChart extends StatelessWidget {
  const _StageEvolutionChart({required this.sessions, required this.project, required this.selectedIndex, required this.onSelected});
  final List<Session> sessions;
  final Project project;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        if (sessions.isEmpty) return;
        final left = 30.0;
        final right = 8.0;
        final usable = math.max(1.0, constraints.maxWidth - left - right);
        final x = (details.localPosition.dx - left).clamp(0.0, usable);
        final index = sessions.length <= 1 ? 0 : (x / usable * (sessions.length - 1)).round().clamp(0, sessions.length - 1);
        onSelected(index);
      },
      child: CustomPaint(
        painter: _StageEvolutionPainter(sessions, project, Theme.of(context).colorScheme, selectedIndex),
        child: const SizedBox.expand(),
      ),
    );
  });
}

class _TempoEvolutionChart extends StatelessWidget {
  const _TempoEvolutionChart({required this.sessions, required this.project, required this.targetTempo, required this.selectedIndex, required this.onSelected});
  final List<Session> sessions;
  final Project project;
  final int targetTempo;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        if (sessions.isEmpty) return;
        const left = 34.0;
        const right = 8.0;
        final usable = math.max(1.0, constraints.maxWidth - left - right);
        final x = (details.localPosition.dx - left).clamp(0.0, usable);
        final index = sessions.length <= 1 ? 0 : (x / usable * (sessions.length - 1)).round().clamp(0, sessions.length - 1);
        onSelected(index);
      },
      child: CustomPaint(
        painter: _TempoEvolutionPainter(sessions, project, targetTempo, Theme.of(context).colorScheme, selectedIndex),
        child: const SizedBox.expand(),
      ),
    );
  });
}

class _StageEvolutionPainter extends CustomPainter {
  _StageEvolutionPainter(this.sessions, this.project, this.scheme, this.selectedIndex);
  final List<Session> sessions;
  final Project project;
  final ColorScheme scheme;
  final int? selectedIndex;

  double? after(Session s, int i, String stage) {
    final direct = stage == 'reading' ? s.newReading : stage == 'hands' ? s.newHandsTogether : stage == 'memory' ? s.newMemory : s.newInterpretation;
    if (direct != null) return direct;
    if (i + 1 < sessions.length) {
      final n = sessions[i + 1];
      return stage == 'reading' ? n.previousReading : stage == 'hands' ? n.previousHandsTogether : stage == 'memory' ? n.previousMemory : n.previousInterpretation;
    }
    return stage == 'reading' ? project.reading : stage == 'hands' ? project.handsTogether : stage == 'memory' ? project.memory : project.interpretation;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const l = 30.0, r = 8.0, t = 8.0, b = 20.0;
    final w = size.width - l - r;
    final h = size.height - t - b;
    final grid = Paint()..color = scheme.outlineVariant..strokeWidth = 1;
    final txt = TextPainter(textDirection: TextDirection.ltr);
    for (final v in [0.0, .5, 1.0]) {
      final y = t + h * (1 - v);
      canvas.drawLine(Offset(l, y), Offset(l + w, y), grid);
      txt.text = TextSpan(text: '${(v * 100).round()}%', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant));
      txt.layout();
      txt.paint(canvas, Offset(0, y - 5));
    }
    final ss = <List<double?>>[
      List.generate(sessions.length, (i) => after(sessions[i], i, 'reading')),
      List.generate(sessions.length, (i) => after(sessions[i], i, 'hands')),
      List.generate(sessions.length, (i) => after(sessions[i], i, 'memory')),
      List.generate(sessions.length, (i) => after(sessions[i], i, 'interpretation')),
    ];
    final pp = <Paint>[
      Paint()..color = scheme.primary..strokeWidth = 2.4,
      Paint()..color = scheme.secondary..strokeWidth = 2.4,
      Paint()..color = scheme.tertiary..strokeWidth = 2.4,
      Paint()..color = scheme.error..strokeWidth = 2.4,
    ];
    for (var k = 0; k < ss.length; k++) {
      Offset? prev;
      for (var i = 0; i < ss[k].length; i++) {
        final v = ss[k][i];
        if (v == null) { prev = null; continue; }
        final x = l + (sessions.length <= 1 ? w / 2 : w * i / (sessions.length - 1));
        final y = t + h * (1 - v.clamp(0, 1));
        final q = Offset(x, y);
        if (prev != null) canvas.drawLine(prev, q, pp[k]);
        canvas.drawCircle(q, i == selectedIndex ? 5 : 3, Paint()..color = pp[k].color);
        prev = q;
      }
    }
    if (selectedIndex != null && selectedIndex! < sessions.length) {
      final x = l + (sessions.length <= 1 ? w / 2 : w * selectedIndex! / (sessions.length - 1));
      canvas.drawLine(Offset(x, t), Offset(x, t + h), Paint()..color = scheme.primary.withOpacity(.35)..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _StageEvolutionPainter old) => old.selectedIndex != selectedIndex || old.sessions != sessions || old.project != project;
}

class _TempoEvolutionPainter extends CustomPainter {
  _TempoEvolutionPainter(this.sessions, this.project, this.targetTempo, this.scheme, this.selectedIndex);
  final List<Session> sessions;
  final Project project;
  final int targetTempo;
  final ColorScheme scheme;
  final int? selectedIndex;

  int? afterTempo(int i) {
    final direct = sessions[i].newTempo;
    if (direct != null && direct > 0) return direct;
    if (i + 1 < sessions.length) {
      final p = sessions[i + 1].previousTempo;
      if (p != null && p > 0) return p;
    }
    return project.currentTempo > 0 ? project.currentTempo : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const l = 34.0, r = 8.0, t = 8.0, b = 18.0;
    final values = List.generate(sessions.length, afterTempo).whereType<int>().where((v) => v > 0).toList();
    if (values.isEmpty) return;
    final minV = math.max(0, ((values.reduce(math.min) * .9) ~/ 5) * 5);
    final raw = targetTempo > 0 ? math.max(targetTempo, values.reduce(math.max)) : values.reduce(math.max);
    final maxV = math.max(minV + 20, ((raw * 1.08).ceil() ~/ 5) * 5);
    final w = size.width - l - r, h = size.height - t - b;
    final grid = Paint()..color = scheme.outlineVariant..strokeWidth = 1;
    final txt = TextPainter(textDirection: TextDirection.ltr);
    for (var j = 0; j <= 2; j++) {
      final y = t + h * (1 - j / 2);
      canvas.drawLine(Offset(l, y), Offset(l + w, y), grid);
      final v = minV + (maxV - minV) * j / 2;
      txt.text = TextSpan(text: '${v.round()}', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant));
      txt.layout();
      txt.paint(canvas, Offset(0, y - 5));
    }
    if (targetTempo > 0) {
      final y = t + h * (1 - ((targetTempo - minV) / (maxV - minV)).clamp(0, 1));
      canvas.drawLine(Offset(l, y), Offset(l + w, y), Paint()..color = scheme.error.withOpacity(.55)..strokeWidth = 1.5);
    }
    final line = Paint()..color = scheme.primary..strokeWidth = 2.5;
    Offset? prev;
    for (var i = 0; i < sessions.length; i++) {
      final v = afterTempo(i);
      if (v == null) { prev = null; continue; }
      final x = l + (sessions.length <= 1 ? w / 2 : w * i / (sessions.length - 1));
      final y = t + h * (1 - ((v - minV) / (maxV - minV)).clamp(0, 1));
      final q = Offset(x, y);
      if (prev != null) canvas.drawLine(prev, q, line);
      canvas.drawCircle(q, i == selectedIndex ? 5 : 3, Paint()..color = line.color);
      prev = q;
    }
    if (selectedIndex != null && selectedIndex! < sessions.length) {
      final x = l + (sessions.length <= 1 ? w / 2 : w * selectedIndex! / (sessions.length - 1));
      canvas.drawLine(Offset(x, t), Offset(x, t + h), Paint()..color = scheme.primary.withOpacity(.35)..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _TempoEvolutionPainter old) => old.selectedIndex != selectedIndex || old.sessions != sessions || old.project != project || old.targetTempo != targetTempo;
}

class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, this.existing, this.totalMinutesPracticed = 0, this.projectSessions = const [], this.scheduledCoachSessions = const [], required this.onScheduleCoachSession, required this.onRunThrough});
  final Project? existing;
  final int totalMinutesPracticed;
  final List<Session> projectSessions;
  final List<PlanItem> scheduledCoachSessions;
  final Future<void> Function(PlanItem) onScheduleCoachSession;
  final Future<void> Function(Project) onRunThrough;
  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  late TextEditingController nameCtrl;
  late TextEditingController goalCtrl;
  String name = '';
  String? method;
  bool priority = false;
  String workFocus = 'Automatique';
  String workIntensity = 'Moyenne';
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
    workFocus = widget.existing?.workFocus ?? 'Automatique';
    workIntensity = widget.existing?.workIntensity ?? 'Moyenne';
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

  Future<void> _showProjectSessionDetails(BuildContext c, Session s) async {
    String pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';
    String feeling(String? v) {
      switch (v) {
        case 'facile': return '😊 Facile';
        case 'correct': return '😐 Correct';
        case 'difficile': return '😓 Difficile';
        default: return '';
      }
    }
    final f = feeling(s.coachFeeling);
    await showDialog<void>(
      context: c,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: [
          Text(widget.existing?.emoji ?? '🎹', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Expanded(child: Text('Détail de la séance')),
        ]),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.existing?.name ?? 'Morceau', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('${s.date.day.toString().padLeft(2, '0')}/${s.date.month.toString().padLeft(2, '0')}/${s.date.year} · ${s.duration} min'),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Chip(label: Text(s.type)),
              if (s.method != null && s.method!.isNotEmpty) Chip(label: Text(s.method!)),
              if (f.isNotEmpty) Chip(label: Text(f)),
              if (s.rating > 0) Chip(label: Text('★' * s.rating)),
            ]),
            if (s.coachFocus != null && s.coachFocus!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Focus travaillé', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.coachFocus!),
            ],
            if (s.coachRecommendation != null && s.coachRecommendation!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('🎯 Recommandation du coach', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.coachRecommendation!, style: const TextStyle(height: 1.35)),
            ],
            if (s.hasProgressSnapshot) ...[
              const SizedBox(height: 14),
              const Text('État avant la séance', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Lecture / mains séparées : ${pct(s.previousReading)}'),
              Text('Mains ensemble : ${pct(s.previousHandsTogether)}'),
              Text('Mémorisation : ${pct(s.previousMemory)}'),
              Text('Interprétation : ${pct(s.previousInterpretation)}'),
            ],
            if (widget.existing != null) ...[
              const SizedBox(height: 14),
              const Text('État actuel du morceau', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Lecture / mains séparées : ${pct(widget.existing!.reading)}'),
              Text('Mains ensemble : ${pct(widget.existing!.handsTogether)}'),
              Text('Mémorisation : ${pct(widget.existing!.memory)}'),
              Text('Interprétation : ${pct(widget.existing!.interpretation)}'),
              if (widget.existing!.currentTempo > 0) Text('Tempo : ${widget.existing!.currentTempo} BPM${widget.existing!.targetTempo > 0 ? ' / cible ${widget.existing!.targetTempo} BPM' : ''}'),
            ],
            if (s.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Notes', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.notes, style: const TextStyle(height: 1.35)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fermer')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final editing = widget.existing != null;
    final media = MediaQuery.of(c);
    final maxDialogHeight = media.size.height * .82;
    final maxDialogWidth = math.min(media.size.width - 32, 760.0);
    final flatTheme = Theme.of(c).copyWith(
      inputDecorationTheme: Theme.of(c).inputDecorationTheme.copyWith(
        border: const UnderlineInputBorder(),
        enabledBorder: const UnderlineInputBorder(),
        focusedBorder: const UnderlineInputBorder(),
        errorBorder: const UnderlineInputBorder(),
        focusedErrorBorder: const UnderlineInputBorder(),
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.only(left: 0, right: 0, top: 10, bottom: 8),
      ),
    );
    return Theme(data: flatTheme, child: AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      title: Text(editing ? 'Modifier le morceau' : 'Nouveau morceau'),
      content: SizedBox(
        width: maxDialogWidth,
        height: math.min(maxDialogHeight, media.size.height - 140),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailSectionHeader(c, 'IDENTITÉ DU MORCEAU', icon: Icons.music_note_outlined),
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
            _detailSectionHeader(c, 'AVANCEMENT', icon: Icons.trending_up_outlined),
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
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.route_outlined, size: 20, color: Theme.of(c).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Les 4 étapes du morceau', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.onSurface))),
            ]),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Mets à jour uniquement ce qui a progressé aujourd’hui.', style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 8),
            _progressSlider('📖  Lecture / mains séparées', reading, (v) => setState(() => reading = v)),
            _progressSlider('🤝  Mains ensemble', handsTogether, (v) => setState(() => handsTogether = v)),
            _progressSlider('🧠  Mémorisation', memory, (v) => setState(() => memory = v)),
            _progressSlider('🎭  Interprétation', interpretation, (v) => setState(() => interpretation = v)),
            const SizedBox(height: 8),
            const Divider(height: 24),
            Row(children: [
              Icon(Icons.speed_outlined, size: 20, color: Theme.of(c).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Tempo et zone de travail', style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: currentTempoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tempo actuel', suffixText: 'BPM'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: targetTempoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tempo cible', suffixText: 'BPM'))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: measuresCtrl, decoration: const InputDecoration(labelText: 'Mesures à travailler', hintText: 'ex. 25–48', prefixIcon: Icon(Icons.format_list_numbered))),
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
            _detailSectionHeader(c, 'STATUT', icon: Icons.flag_outlined),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: statusIsManual && projectStatuses.contains(status) ? status : '__AUTO__',
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.timeline),
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
            const SizedBox(height: 10),
            const Divider(height: 24),
            Row(children: [
              Icon(Icons.track_changes_outlined, size: 20, color: Theme.of(c).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Besoin de travail actuel', style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            const Text('Indique ce qui mérite le plus de temps maintenant. « Automatique » utilise les étapes du morceau.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: workFocus,
                  decoration: const InputDecoration(labelText: 'Travail principal', prefixIcon: Icon(Icons.track_changes_outlined)),
                  items: workFocuses.map((v) => DropdownMenuItem(value: v, child: Text('${workFocusEmoji(v)}  $v'))).toList(),
                  onChanged: (v) => setState(() => workFocus = v ?? 'Automatique'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: workIntensity,
                  decoration: const InputDecoration(labelText: 'Intensité du besoin', prefixIcon: Icon(Icons.speed_outlined)),
                  items: workIntensities.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setState(() => workIntensity = v ?? 'Moyenne'),
                ),
                const SizedBox(height: 8),
            Text(
              workFocus == 'Automatique'
                  ? 'Le planning choisira automatiquement l’étape la plus faible.'
                  : 'Durée indicative : ${workFocusMinMinutes(workFocus)}–${workFocusMaxMinutes(workFocus)} min par bloc.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Priorité'),
              subtitle: const Text('Recevra plus de temps dans les propositions de planning'),
              value: priority,
              onChanged: (v) => setState(() => priority = v),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 14),
              const Divider(height: 26),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.play_circle_outline, color: Theme.of(c).colorScheme.secondary, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('RUN-THROUGH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .6)),
                  const SizedBox(height: 3),
                  const Text('Jouer le morceau en continu du début à la fin pour vérifier ce qui tient réellement.', style: TextStyle(fontSize: 12, height: 1.3)),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
                    onPressed: () => widget.onRunThrough(widget.existing!),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Lancer un run-through'),
                  )),
                ])),
              ]),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 4),
              if (widget.projectSessions.isNotEmpty) ...[
                _ProjectCoachDashboard(project: widget.existing!, sessions: widget.projectSessions, scheduledCoachSessions: widget.scheduledCoachSessions, onScheduleCoachSession: widget.onScheduleCoachSession),
                const SizedBox(height: 8),
                _ProjectEvolutionSection(project: widget.existing!, sessions: widget.projectSessions),
                const SizedBox(height: 8),
              ],
              Text(
                'Sessions réalisées (${widget.projectSessions.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (widget.projectSessions.isNotEmpty) ...[
                Builder(
                  builder: (summaryContext) {
                    final recent = widget.projectSessions.take(3).toList();
                    final recentMinutes = recent.fold<int>(0, (sum, s) => sum + s.duration);
                    final avgRating = recent.fold<int>(0, (sum, s) => sum + s.rating) / recent.length;
                    final feelings = recent.map((s) {
                      switch (s.coachFeeling) {
                        case 'facile': return '😊';
                        case 'correct': return '😐';
                        case 'difficile': return '😓';
                        default: return '·';
                      }
                    }).join(' ');
                    final hasFeeling = recent.any((s) => s.coachFeeling != null);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.insights_outlined, size: 18, color: Theme.of(summaryContext).colorScheme.primary),
                                const SizedBox(width: 7),
                                const Expanded(child: Text('Les 3 dernières séances', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                                Text('${recent.length} séance${recent.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              children: [
                                Text('⏱ $recentMinutes min', style: const TextStyle(fontSize: 12)),
                                Text('★ ${avgRating.toStringAsFixed(1)} / 5', style: const TextStyle(fontSize: 12)),
                                if (hasFeeling) Text('Ressenti : $feelings', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            if (recent.length >= 2) ...[
                              const SizedBox(height: 6),
                              Text(
                                recent.first.coachFeeling == 'difficile'
                                    ? '💡 Dernière séance difficile : privilégier la consolidation avant d’accélérer.'
                                    : recent.first.coachFeeling == 'facile'
                                        ? '🚀 Dernière séance facile : une légère montée en difficulté peut être envisagée.'
                                        : recent.first.coachFeeling == 'correct'
                                            ? '🎯 Dernière séance correcte : poursuivre le travail ciblé.'
                                            : '📈 Historique récent disponible pour suivre l’évolution.',
                                style: TextStyle(fontSize: 11, color: Theme.of(summaryContext).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                    );
                  },
                ),
              ],
              if (widget.projectSessions.isEmpty)
                const Text('Aucune session enregistrée pour ce morceau pour l\'instant.', style: TextStyle(color: Colors.grey, fontSize: 13))
              else
                ...widget.projectSessions.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                          onTap: () => _showProjectSessionDetails(c, s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 70,
                                  child: Text('${s.date.day}/${s.date.month}/${s.date.year}', style: const TextStyle(fontSize: 12)),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${s.duration} min · ${s.type}${s.method != null ? ' · ${s.method}' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      if (s.coachFeeling != null)
                                        Text(
                                          s.coachFeeling == 'facile' ? '😊 Facile' : s.coachFeeling == 'correct' ? '😐 Correct' : s.coachFeeling == 'difficile' ? '😓 Difficile' : '',
                                          style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                        ),
                                    ],
                                  ),
                                ),
                                if (s.rating > 0) Text('★' * s.rating, style: const TextStyle(color: Colors.amber, fontSize: 11)),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right, size: 19, color: Theme.of(c).colorScheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                      ),
                    )),
            ],
          ],
        ),
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
                      workFocus: workFocus,
                      workIntensity: workIntensity,
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
                      lastModified: widget.existing?.lastModified ?? DateTime.now(),
                    ),
                  );
                },
          child: const Text('Enregistrer'),
        ),
      ],
    ));
  }
}// ---------------------------------------------------------------------------
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
    required this.onCoachAdjustmentSeen,
    required this.projectById,
    required this.sessions,
    required this.onOpenCoachLog,
    required this.coachRestDayKeys,
    required this.dailyCapacity,
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
  final void Function(PlanItem) onCoachAdjustmentSeen;
  final Project? Function(String?) projectById;
  final List<Session> sessions;
  final VoidCallback onOpenCoachLog;
  final Set<String> coachRestDayKeys;
  final List<int> dailyCapacity;

  @override
  State<Week> createState() => _WeekState();
}

class _WeekState extends State<Week> with SingleTickerProviderStateMixin {
  DateTime? filtreDate;
  late final AnimationController _coachPulseController;
  final ScrollController _weekScrollController = ScrollController();
  final Map<DateTime, GlobalKey> _dayKeys = {};
  bool _todayPositioned = false;

  @override
  void initState() {
    super.initState();
    _coachPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      lowerBound: .45,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  void _positionOnToday() {
    if (_todayPositioned || filtreDate != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _todayPositioned || filtreDate != null) return;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final contextForDay = _dayKeys[today]?.currentContext;
      if (contextForDay == null) return;
      _todayPositioned = true;
      await Scrollable.ensureVisible(
        contextForDay,
        alignment: 0.08,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _coachPulseController.dispose();
    _weekScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant Week oldWidget) {
    super.didUpdateWidget(oldWidget);
    _todayPositioned = false;
    _positionOnToday();
  }
  String filtreMotCle = '';

  static String weekday(int n) => ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'][n - 1];

  Session? _sourceSession(PlanItem item) {
    final id = item.sourceSessionId;
    if (id == null) return null;
    return widget.sessions.where((s) => s.id == id).firstOrNull;
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  String _dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isCoachRestDay(DateTime d) => widget.coachRestDayKeys.contains(_dayKey(d));

  String _emptyDayLabel(DateTime d) {
    if (widget.dailyCapacity[d.weekday - 1] <= 0) return 'Indisponible';
    if (_isCoachRestDay(d)) return 'Repos conseillé par le coach';
    return 'Aucune séance planifiée';
  }

  String _emptyDayHint(DateTime d) {
    if (widget.dailyCapacity[d.weekday - 1] <= 0) return 'Journée déclarée indisponible dans tes disponibilités.';
    if (_isCoachRestDay(d)) return 'Le planning automatique a volontairement laissé cette journée libre pour équilibrer la semaine.';
    return 'La journée est disponible, mais aucune séance n’est actuellement planifiée.';
  }

  bool _wasAdjustedByCoach(PlanItem item) =>
      !item.completed && item.sourceSessionId == null && item.coachAdjusted;

  bool _hasUnseenCoachAdjustment(PlanItem item) =>
      _wasAdjustedByCoach(item) && !item.coachAdjustmentSeen;

  Widget _coachPulseDot(BuildContext c, {required bool visible}) {
    if (!visible) return const SizedBox.shrink();
    final color = Theme.of(c).colorScheme.primary;
    return AnimatedBuilder(
      animation: _coachPulseController,
      builder: (_, __) => Opacity(
        opacity: _coachPulseController.value,
        child: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(.30), blurRadius: 7, spreadRadius: 1)],
          ),
        ),
      ),
    );
  }

  Future<void> _showCoachAdjustmentDetail(BuildContext c, PlanItem item) async {
    if (!_wasAdjustedByCoach(item)) return;
    final delta = item.duration - item.plannedDuration;
    final evolution = delta < 0
        ? 'Le coach a allégé cette séance.'
        : delta > 0
            ? 'Le coach a renforcé cette séance.'
            : 'Le coach a ajusté cette séance.';
    final detail = delta.abs() >= 1
        ? '${item.plannedDuration} min → ${item.duration} min'
        : '${item.duration} min';

    if (!item.coachAdjustmentSeen) {
      item.coachAdjustmentSeen = true;
      widget.onCoachAdjustmentSeen(item);
      if (mounted) setState(() {});
    }

    await showDialog<void>(
      context: c,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: [
          Icon(Icons.auto_awesome, color: Theme.of(dialogContext).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Modification du coach')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(detail, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(dialogContext).colorScheme.primary)),
            const SizedBox(height: 8),
            Text(evolution),
            if ((item.coachAdjustmentReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(item.coachAdjustmentReason!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Text('Cette modification concerne le planning à venir. Les séances déjà réalisées ne sont jamais modifiées.', style: TextStyle(color: Theme.of(dialogContext).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('J’ai compris')),
        ],
      ),
    );
  }

  bool _dayHasCoachAdjustment(List<PlanItem> items) => items.any(_wasAdjustedByCoach);
  bool _dayHasUnseenCoachAdjustment(List<PlanItem> items) => items.any(_hasUnseenCoachAdjustment);

  Widget _coachAdjustmentBanner(BuildContext c, List<PlanItem> items) {
    if (!_dayHasCoachAdjustment(items)) return const SizedBox.shrink();
    final adjusted = items.where(_wasAdjustedByCoach).length;
    final unseen = _dayHasUnseenCoachAdjustment(items);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final first = items.firstWhere(_wasAdjustedByCoach);
          await _showCoachAdjustmentDetail(c, first);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: Theme.of(c).colorScheme.primary.withOpacity(.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(c).colorScheme.primary.withOpacity(.18)),
          ),
          child: Row(children: [
            _coachPulseDot(c, visible: true),
            const SizedBox(width: 8),
            Icon(Icons.auto_awesome, size: 17, color: Theme.of(c).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Planning ajusté par le coach · $adjusted modification${adjusted > 1 ? 's' : ''}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.onSurface),
              ),
            ),
            Text(unseen ? 'Voir' : 'Détail', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Theme.of(c).colorScheme.primary)),
          ]),
        ),
      ),
    );
  }

  Widget _coachAdjustmentLabel(BuildContext c, PlanItem item) {
    if (!_wasAdjustedByCoach(item)) return const SizedBox.shrink();
    final delta = item.duration - item.plannedDuration;
    final unseen = _hasUnseenCoachAdjustment(item);
    final text = delta < 0
        ? 'Coach : ${item.duration} min au lieu de ${item.plannedDuration} min · séance allégée'
        : 'Coach : ${item.duration} min au lieu de ${item.plannedDuration} min · séance renforcée';
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showCoachAdjustmentDetail(c, item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(c).colorScheme.primary.withOpacity(.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(c).colorScheme.primary.withOpacity(.18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _coachPulseDot(c, visible: true),
            if (unseen) const SizedBox(width: 7),
            Icon(Icons.auto_awesome, size: 14, color: Theme.of(c).colorScheme.primary),
            const SizedBox(width: 5),
            Flexible(child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.primary))),
          ]),
        ),
      ),
    );
  }

  Widget _plannedVsRealized(BuildContext c, PlanItem item) {
    final planned = item.plannedDuration > 0 ? item.plannedDuration : item.duration;
    final source = _sourceSession(item);
    if (!item.completed || source == null || planned <= 0) {
      return const SizedBox.shrink();
    }
    final realized = source.duration;
    final ratio = planned > 0 ? realized / planned : 0.0;
    final delta = realized - planned;
    final label = ratio >= 0.98 && ratio <= 1.02
        ? 'Objectif respecté'
        : delta < 0
            ? '${(-delta)} min en moins'
            : '+$delta min';
    final color = ratio >= 0.9 && ratio <= 1.2
        ? Colors.green.shade700
        : (ratio < 0.9 ? Colors.orange.shade700 : Colors.deepPurple.shade700);
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withOpacity(.18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.compare_arrows_outlined, size: 15, color: color),
            const SizedBox(width: 5),
            Expanded(child: Text(
              '$planned min prévues → $realized min réalisées',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
            )),
            Text('${(ratio * 100).round()} %', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
          ]),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ]),
      ),
    );
  }

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
            IconButton(onPressed: widget.onOpenCoachLog, icon: const Icon(Icons.psychology_outlined), tooltip: 'Journal du coach'),
            IconButton(onPressed: widget.onClear, icon: const Icon(Icons.playlist_remove), tooltip: 'Effacer le planning'),
            IconButton(onPressed: widget.onAdd, icon: const Icon(Icons.add)),
          ],
        ),
        Expanded(
          child: ListView(
            controller: _weekScrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                    const SizedBox(height: 10),
                    Text(
                      'Ce compteur mesure le temps réellement joué, indépendamment du planning.',
                      style: TextStyle(fontSize: 10.5, color: Theme.of(c).colorScheme.onSurfaceVariant),
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
              if (filterActive && sorted.isEmpty)
                emptyState('Aucune séance ne correspond à ce filtre.')
              else
                ...(() {
                  final grouped = groupedByDay(sorted);
                  if (!filterActive) {
                    final monday = startOfWeek(DateTime.now());
                    for (var i = 0; i < 7; i++) {
                      final d = DateTime(monday.year, monday.month, monday.day + i);
                      grouped.putIfAbsent(d, () => <PlanItem>[]);
                    }
                  }
                  final entries = grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
                  return entries.expand((entry) => [
                      Padding(
                        key: _dayKeys.putIfAbsent(
                          DateTime(entry.key.year, entry.key.month, entry.key.day),
                          () => GlobalKey(),
                        ),
                        padding: const EdgeInsets.only(top: 11, bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Expanded(
                            child: Row(children: [
                              Flexible(
                                child: Text(
                                  '${weekday(entry.key.weekday)} ${entry.key.day}/${entry.key.month}',
                                  style: TextStyle(
                                    fontSize: _isToday(entry.key) ? 18 : 15.5,
                                    height: 1.05,
                                    letterSpacing: _isToday(entry.key) ? .15 : 0,
                                    fontWeight: FontWeight.w900,
                                    color: _isToday(entry.key) ? Theme.of(c).colorScheme.primary : Colors.deepPurple,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_dayHasUnseenCoachAdjustment(entry.value)) ...[
                                Semantics(
                                  label: 'Modification du coach non consultée',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () async {
                                      final first = entry.value.firstWhere(_hasUnseenCoachAdjustment);
                                      await _showCoachAdjustmentDetail(c, first);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(3),
                                      child: _coachPulseDot(c, visible: true),
                                    ),
                                  ),
                                ),
                                Text(
                                  'COACH',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .5,
                                    color: Theme.of(c).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ]),
                          ),
                          if (_isToday(entry.key))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: Theme.of(c).colorScheme.primary.withOpacity(.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Theme.of(c).colorScheme.primary.withOpacity(.24)),
                              ),
                              child: Text("AUJOURD'HUI", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .35, color: Theme.of(c).colorScheme.primary)),
                            ),
                        ]),
                      ),
                      _coachAdjustmentBanner(c, entry.value),
                      if (entry.value.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: _isToday(entry.key)
                                  ? Theme.of(c).colorScheme.primary.withOpacity(.055)
                                  : Theme.of(c).colorScheme.surfaceContainerHighest.withOpacity(.34),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isToday(entry.key)
                                    ? Theme.of(c).colorScheme.primary.withOpacity(.20)
                                    : Theme.of(c).dividerColor.withOpacity(.45),
                              ),
                            ),
                            child: Row(children: [
                              Icon(
                                widget.dailyCapacity[entry.key.weekday - 1] <= 0
                                    ? Icons.event_busy_outlined
                                    : _isCoachRestDay(entry.key)
                                        ? Icons.hotel_outlined
                                        : Icons.event_available_outlined,
                                size: 20,
                                color: widget.dailyCapacity[entry.key.weekday - 1] <= 0
                                    ? Colors.grey
                                    : Theme.of(c).colorScheme.primary,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(_emptyDayLabel(entry.key), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                                  const SizedBox(height: 2),
                                  Text(_emptyDayHint(entry.key), style: TextStyle(fontSize: 10.5, color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.25)),
                                ]),
                              ),
                              if (widget.dailyCapacity[entry.key.weekday - 1] > 0)
                                IconButton(
                                  tooltip: 'Ajouter une séance',
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: widget.onAdd,
                                ),
                            ]),
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
                                              _coachAdjustmentLabel(c, x),
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
                                              _plannedVsRealized(c, x),
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
                    ]);
                })(),
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
  const BadgesScreen({super.key, required this.badges, required this.onReset});
  final List<AppBadge> badges;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext c) {
    final earnedCount = badges.where((b) => b.earned).length;
    final unlocked = earnedCount == badges.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Badges  •  $earnedCount/${badges.length}'),
        actions: [
          IconButton(
            tooltip: 'Réinitialiser les badges',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: onReset,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: CardBox(
              child: Row(
                children: [
                  Container(
                    width: 54, height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: unlocked ? [Colors.amber.shade300, Colors.orange.shade700] : [Colors.indigo.shade200, Colors.indigo.shade600]),
                    ),
                    child: Icon(unlocked ? Icons.emoji_events_rounded : Icons.auto_awesome_rounded, color: Colors.white, size: 29),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(unlocked ? 'Collection complète ! 🏆' : 'Ta collection de badges', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(unlocked ? 'Tous les badges sont débloqués.' : 'Continue à jouer : le prochain badge est peut-être tout proche !', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                  ])),
                ],
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .76),
              itemCount: badges.length,
              itemBuilder: (_, i) {
                final b = badges[i];
                final ratio = b.target <= 0 ? 1.0 : (b.progress / b.target).clamp(0.0, 1.0);
                return _BadgeCard(badge: b, ratio: ratio);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge, required this.ratio});
  final AppBadge badge;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: b.earned
              ? [Colors.amber.shade50, Colors.orange.shade100]
              : [Theme.of(context).colorScheme.surface, Colors.grey.shade100],
        ),
        border: Border.all(color: b.earned ? Colors.amber.shade300 : Colors.grey.shade300, width: b.earned ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.07), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          children: [
            Stack(alignment: Alignment.center, children: [
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: b.earned ? [Colors.amber.shade300, Colors.deepOrange.shade400] : [Colors.grey.shade300, Colors.grey.shade400]),
                  boxShadow: b.earned ? [BoxShadow(color: Colors.orange.withOpacity(.28), blurRadius: 12, spreadRadius: 2)] : null,
                ),
              ),
              Text(b.emoji, style: TextStyle(fontSize: 35, color: b.earned ? null : Colors.grey.shade600)),
              if (!b.earned) Positioned(right: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(5), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.lock_rounded, size: 15, color: Colors.grey))),
            ]),
            const SizedBox(height: 10),
            Text(b.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: b.earned ? Colors.brown.shade800 : Colors.grey.shade700)),
            const SizedBox(height: 5),
            Expanded(child: Text(b.description, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 11))),
            const SizedBox(height: 7),
            ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: ratio, minHeight: 7, backgroundColor: Colors.grey.shade300)),
            const SizedBox(height: 5),
            Text(b.earned ? 'DÉBLOQUÉ ✨' : '${b.progress} / ${b.target}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .5, color: b.earned ? Colors.orange.shade800 : Colors.grey.shade600)),
          ],
        ),
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
        CardBox(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(c, Icons.compare_arrows_outlined, 'Prévu / réalisé',
              subtitle: 'Comparaison entre le planning et les séances réellement effectuées.'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _statTile(c, icon: Icons.event_note_outlined, label: 'Planifié', value: '${bilan.plannedMinutes} min', sub: '${bilan.plannedSessions} séance${bilan.plannedSessions > 1 ? 's' : ''}')),
              const SizedBox(width: 10),
              Expanded(child: _statTile(c, icon: Icons.play_circle_outline, label: 'Réalisé', value: '${bilan.realizedPlannedMinutes} min', sub: '${bilan.completedPlannedSessions} séance${bilan.completedPlannedSessions > 1 ? 's' : ''}')),
            ]),
            if (bilan.plannedMinutes > 0) ...[
              const SizedBox(height: 12),
              Builder(builder: (_) {
                final ratio = bilan.realizedPlannedMinutes / bilan.plannedMinutes;
                final delta = bilan.realizedPlannedMinutes - bilan.plannedMinutes;
                final pct = (ratio * 100).round();
                final color = ratio >= .9 && ratio <= 1.2
                    ? Colors.green.shade700
                    : (ratio < .9 ? Colors.orange.shade700 : Colors.deepPurple.shade700);
                final deltaText = delta == 0 ? 'Écart : 0 min' : delta < 0 ? 'Écart : ${delta} min' : 'Écart : +$delta min';
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Adhérence au planning : $pct %', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color))),
                    Text(deltaText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.onSurfaceVariant)),
                  ]),
                  const SizedBox(height: 6),
                  progress(ratio.clamp(0, 1).toDouble()),
                  const SizedBox(height: 4),
                  Text(
                    'Le réalisé correspond aux séances du planning effectivement terminées. Les séances libres ne sont pas comptées dans ce taux.',
                    style: TextStyle(fontSize: 10.5, color: Theme.of(c).colorScheme.onSurfaceVariant),
                  ),
                ]);
              }),
            ],
          ]),
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

// ---------------------------------------------------------------------------
// Vue globale de progression
// ---------------------------------------------------------------------------

class ProgressDashboardScreen extends StatelessWidget {
  const ProgressDashboardScreen({
    super.key,
    required this.projects,
    required this.sessions,
    required this.weeklyHistory,
    required this.onOpenProject,
    required this.onStartRecommended,
  });

  final List<Project> projects;
  final List<Session> sessions;
  final List<WeeklyBilan> Function({int weeks}) weeklyHistory;
  final Future<void> Function(Project) onOpenProject;
  final void Function(PlanItem) onStartRecommended;

  @override
  Widget build(BuildContext c) {
    final active = projects.toList();
    final avgProgress = projects.isEmpty
        ? 0.0
        : projects.fold<double>(0, (sum, p) => sum + p.progress) / projects.length;
    final completed = projects.where((p) => p.progress >= 1).length;
    final maintenance = projects.where((p) => p.effectiveStatus == 'Répertoire d’entretien').length;
    final priority = active.where((p) => p.priority).toList();

    final stageValues = <String, double>{
      'Lecture': projects.isEmpty ? 0 : projects.fold<double>(0, (a, p) => a + p.reading) / projects.length,
      'Mains ensemble': projects.isEmpty ? 0 : projects.fold<double>(0, (a, p) => a + p.handsTogether) / projects.length,
      'Mémorisation': projects.isEmpty ? 0 : projects.fold<double>(0, (a, p) => a + p.memory) / projects.length,
      'Interprétation': projects.isEmpty ? 0 : projects.fold<double>(0, (a, p) => a + p.interpretation) / projects.length,
    };
    final weakestStage = stageValues.entries.reduce((a, b) => a.value <= b.value ? a : b);

    final tempoMeasured = <Project, int>{};
    for (final p in projects) {
      final values = sessions
          .where((s) => s.projectId == p.id && s.type == 'Run-through' && s.runThroughCompleted == true)
          .map((s) => s.runThroughEndTempo ?? 0)
          .where((v) => v > 0)
          .toList();
      if (values.isNotEmpty && p.targetTempo > 0) {
        tempoMeasured[p] = values.reduce(math.max);
      }
    }
    final tempoMastery = tempoMeasured.isEmpty
        ? null
        : tempoMeasured.entries.fold<double>(0, (a, e) => a + (e.value / e.key.targetTempo).clamp(0.0, 1.0)) / tempoMeasured.length;

    final recent = [...sessions]..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();
    final recent7 = recent.where((s) {
      final age = now.difference(s.date);
      return !age.isNegative && age < const Duration(days: 7);
    }).toList();
    final recentMinutes = recent7.fold(0, (a, s) => a + s.duration);
    final difficult = recent7.where((s) => s.coachFeeling == 'difficile').length;

    final history = weeklyHistory(weeks: 4);
    final trend = history.length >= 2 ? history.last.totalMinutes - history[history.length - 2].totalMinutes : 0;

    final mediaWidth = MediaQuery.sizeOf(c).width;
    final compact = mediaWidth < 600;
    Widget progress(double v) => ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: v, minHeight: 7));

    return Scaffold(
      appBar: AppBar(title: const Text('Vue globale de progression')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 14, compact ? 12 : 20, 20),
        children: [
          CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(c, Icons.insights, 'Où en suis-je ?', subtitle: 'Une vision synthétique de tes morceaux, de ta maîtrise et de ta régularité.'),
            const SizedBox(height: 16),
            if (compact) ...[
              _progressMetric(c, 'Progression moyenne', avgProgress, '${(avgProgress * 100).round()} %'),
              const SizedBox(height: 16),
              _progressMetric(c, 'Maîtrise tempo', tempoMastery ?? 0, tempoMastery == null ? '—' : '${(tempoMastery * 100).round()} %'),
            ] else
              Row(children: [
                Expanded(child: _progressMetric(c, 'Progression moyenne', avgProgress, '${(avgProgress * 100).round()} %')),
                const SizedBox(width: 16),
                Expanded(child: _progressMetric(c, 'Maîtrise tempo', tempoMastery ?? 0, tempoMastery == null ? '—' : '${(tempoMastery * 100).round()} %')),
              ]),
          ])),
          const SizedBox(height: 16),
          if (compact)
            Column(children: [
              SizedBox(width: double.infinity, child: _statTile(c, icon: Icons.music_note, label: 'Morceaux', value: '${projects.length}', sub: '$completed terminé${completed > 1 ? 's' : ''}')),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: _statTile(c, icon: Icons.build_circle_outlined, label: 'Entretien', value: '$maintenance')),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: _statTile(c, icon: Icons.star_outline, label: 'Priorités', value: '${priority.length}')),
            ])
          else
            Row(children: [
              Expanded(child: _statTile(c, icon: Icons.music_note, label: 'Morceaux', value: '${projects.length}', sub: '$completed terminé${completed > 1 ? 's' : ''}')),
              const SizedBox(width: 10),
              Expanded(child: _statTile(c, icon: Icons.build_circle_outlined, label: 'Entretien', value: '$maintenance')),
              const SizedBox(width: 10),
              Expanded(child: _statTile(c, icon: Icons.star_outline, label: 'Priorités', value: '${priority.length}')),
            ]),
          const SizedBox(height: 16),
          CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(c, Icons.donut_small_outlined, 'État du répertoire', subtitle: 'Répartition actuelle de tes morceaux.'),
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final statusCounts = <String, int>{};
              for (final p in projects) {
                statusCounts[p.effectiveStatus] = (statusCounts[p.effectiveStatus] ?? 0) + 1;
              }
              const statuses = ['À découvrir', 'En cours de déchiffrage', 'En mémorisation', 'Acquis', 'Répertoire d’entretien'];
              Widget progress(double v) => ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: v, minHeight: 7));
              return Column(children: [
                for (final s in statuses)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                    Expanded(child: Text(s, style: const TextStyle(fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    SizedBox(width: compact ? 80 : 90, child: progress(projects.isEmpty ? 0 : ((statusCounts[s] ?? 0) / projects.length).clamp(0.0, 1.0).toDouble())),
                    const SizedBox(width: 8),
                    Text('${statusCounts[s] ?? 0}'),
                  ])),
              ]);
            }),
          ])),
          const SizedBox(height: 16),
          CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(c, Icons.workspace_premium_outlined, 'Maîtrise des morceaux', subtitle: 'Progression + tempo + Run-through lorsqu’il est disponible.'),
            const SizedBox(height: 12),
            if (active.isEmpty)
              Text('Aucun morceau actif à évaluer.', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant))
            else
              ...([
                for (final p in active)
                  MapEntry<Project, double>(p, pieceMasteryScore(p, sessions.where((s) => s.projectId == p.id).toList())),
              ]..sort((a, b) => a.value.compareTo(b.value)))
                  .take(compact ? 4 : 6)
                  .map((entry) {
                    final p = entry.key;
                    final score = entry.value;
                    final tempoRatio = p.targetTempo > 0 && p.currentTempo > 0
                        ? (p.currentTempo / p.targetTempo).clamp(0.0, 1.0)
                        : null;
                    final runs = sessions.where((s) => s.projectId == p.id && s.type == 'Run-through').toList();
                    final completedRuns = runs.where((s) => s.runThroughCompleted == true).length;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onOpenProject(p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Text(p.emoji),
                              const SizedBox(width: 7),
                              Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                              Text('${score.round()} %', style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(c).colorScheme.primary)),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right, size: 16, color: Theme.of(c).colorScheme.onSurfaceVariant),
                            ]),
                            const SizedBox(height: 5),
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (score / 100).clamp(0.0, 1.0), minHeight: 7)),
                            const SizedBox(height: 4),
                            Text(
                              '${masteryLabel(score)} · étapes ${(p.progress * 100).round()} %'
                              '${tempoRatio != null ? ' · tempo ${(tempoRatio * 100).round()} %' : ''}'
                              '${completedRuns > 0 ? ' · $completedRuns Run-through terminé${completedRuns > 1 ? 's' : ''}' : ''}',
                              style: TextStyle(fontSize: 10.5, color: Theme.of(c).colorScheme.onSurfaceVariant),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }),
          ])),
          const SizedBox(height: 16),
          CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(c, Icons.stacked_bar_chart, 'Les 4 étapes de progression'),
            const SizedBox(height: 14),
            for (final e in stageValues.entries) ...[
              Row(children: [Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))), Text('${(e.value * 100).round()} %')]),
              const SizedBox(height: 5),
              progress(e.value),
              const SizedBox(height: 10),
            ],
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Theme.of(c).colorScheme.primaryContainer.withOpacity(.45)),
              child: Row(children: [
                Icon(Icons.auto_awesome, size: 18, color: Theme.of(c).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Le point à renforcer en priorité : ${weakestStage.key} (${(weakestStage.value * 100).round()} %).', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              ]),
            ),
          ])),
          const SizedBox(height: 16),
          CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(c, Icons.speed_outlined, 'Maîtrise du tempo', subtitle: tempoMeasured.isEmpty ? 'Aucun Run-through terminé avec tempo mesuré.' : '${tempoMeasured.length} morceau${tempoMeasured.length > 1 ? 'x' : ''} mesuré${tempoMeasured.length > 1 ? 's' : ''}'),
            if (tempoMeasured.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final e in (tempoMeasured.entries.toList()..sort((a, b) => (a.value / a.key.targetTempo).compareTo(b.value / b.key.targetTempo))).take(5)) ...[
                Builder(builder: (context) {
                  final runs = sessions.where((s) => s.projectId == e.key.id && s.type == 'Run-through' && s.runThroughCompleted == true && (s.runThroughEndTempo ?? 0) > 0).toList()..sort((a, b) => b.date.compareTo(a.date));
                  final lastTempo = runs.isNotEmpty ? runs.first.runThroughEndTempo! : null;
                  final delta = lastTempo != null && runs.length >= 2 ? lastTempo - (runs[1].runThroughEndTempo ?? lastTempo) : null;
                  final ratio = e.key.targetTempo > 0 ? ((e.value / e.key.targetTempo).clamp(0.0, 1.0)).toDouble() : 1.0;
                  final advice = ratio >= 1.0
                      ? 'Conseil : tempo cible atteinte — travailler maintenant la régularité et l’interprétation.'
                      : ratio >= .90
                          ? 'Conseil : proche de la cible — consolider avant de monter le tempo.'
                          : delta != null && delta > 0
                              ? 'Conseil : progression positive — poursuivre par petites hausses de tempo.'
                              : ratio >= .80
                                  ? 'Conseil : continuité en bonne voie — stabiliser ce tempo avant de monter.'
                                  : 'Conseil : revenir au tempo confortable et sécuriser les passages fragiles.';
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onOpenProject(e.key),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Text(e.key.emoji), const SizedBox(width: 7), Expanded(child: Text(e.key.name, style: const TextStyle(fontWeight: FontWeight.w600))), Text('${e.value}/${e.key.targetTempo} BPM', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(width: 4), Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)]),
                      const SizedBox(height: 5),
                      progress(ratio),
                      const SizedBox(height: 4),
                      Text(delta == null ? 'Dernier Run-through : ${lastTempo ?? e.value} BPM' : 'Dernier : $lastTempo BPM · évolution ${delta >= 0 ? '+' : ''}$delta BPM', style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 3),
                      Text(advice, style: TextStyle(fontSize: 10.2, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 7),
                    ])),
                  );
                }),
              ],
            ],
          ])),
          const SizedBox(height: 16),
          CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(c, Icons.calendar_today_outlined, 'Régularité récente'),
            const SizedBox(height: 12),
            if (compact)
              Column(children: [
                SizedBox(width: double.infinity, child: _statTile(c, icon: Icons.timer_outlined, label: '7 derniers jours', value: '${recentMinutes} min')),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: _statTile(c, icon: Icons.warning_amber_outlined, label: 'Séances difficiles', value: '$difficult')),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: _statTile(c, icon: trend >= 0 ? Icons.trending_up : Icons.trending_down, label: 'Vs semaine précédente', value: trend == 0 ? 'Stable' : '${trend > 0 ? '+' : ''}$trend min', accent: trend >= 0 ? Colors.green.shade700 : Colors.deepOrange.shade700)),
              ])
            else
              Row(children: [
                Expanded(child: _statTile(c, icon: Icons.timer_outlined, label: '7 derniers jours', value: '${recentMinutes} min')),
                const SizedBox(width: 10),
                Expanded(child: _statTile(c, icon: Icons.warning_amber_outlined, label: 'Séances difficiles', value: '$difficult')),
                const SizedBox(width: 10),
                Expanded(child: _statTile(c, icon: trend >= 0 ? Icons.trending_up : Icons.trending_down, label: 'Vs semaine précédente', value: trend == 0 ? 'Stable' : '${trend > 0 ? '+' : ''}$trend min', accent: trend >= 0 ? Colors.green.shade700 : Colors.deepOrange.shade700)),
              ]),
          ])),
          const SizedBox(height: 16),
          CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader(c, Icons.psychology_outlined, 'Le rôle du coach', subtitle: 'Les décisions d’action sont regroupées dans Mission du jour.'),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.today_outlined, size: 20, color: Theme.of(c).colorScheme.primary),
              const SizedBox(width: 9),
              Expanded(child: Text('Mission du jour te dit quoi travailler aujourd’hui. La Progression explique où tu en es : morceaux en avance ou en difficulté, tempo, étapes, Run-through et régularité.', style: TextStyle(fontSize: 12, height: 1.35, color: Theme.of(c).colorScheme.onSurfaceVariant))),
            ]),
          ])),
          const SizedBox(height: 12),
          Text('Cette vue complète le bilan hebdomadaire : elle regarde l’ensemble des morceaux et non uniquement la semaine en cours.', style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _progressMetric(BuildContext c, String label, double value, String text) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
    const SizedBox(height: 7),
    Text(text, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
    const SizedBox(height: 7),
    progress(value),
  ]);
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
          Padding(
            padding: const EdgeInsets.only(top: 2),
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
    final flatTheme = Theme.of(c).copyWith(
      inputDecorationTheme: Theme.of(c).inputDecorationTheme.copyWith(
        border: const UnderlineInputBorder(),
        enabledBorder: const UnderlineInputBorder(),
        focusedBorder: const UnderlineInputBorder(),
        errorBorder: const UnderlineInputBorder(),
        focusedErrorBorder: const UnderlineInputBorder(),
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.only(left: 0, right: 0, top: 10, bottom: 8),
      ),
    );
    return Theme(data: flatTheme, child: AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      title: Text(editing ? 'Modifier la séance' : 'Planifier une séance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailSectionHeader(c, 'QUAND', icon: Icons.calendar_today_outlined),
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
            _detailSectionHeader(c, 'TRAVAIL À PLANIFIER', icon: Icons.event_note_outlined),
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
    ));
  }
}

// V110 — boucle coach fiabilisee, adaptation session→prochaine, objectifs relies, planning/session audits.
