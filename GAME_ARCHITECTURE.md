# Deep State - Complete Game Architecture Documentation

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [Core Game Loop](#2-core-game-loop)
3. [Data Architecture](#3-data-architecture)
4. [Institution System](#4-institution-system)
5. [Event System](#5-event-system)
6. [Crisis System](#6-crisis-system)
7. [Dependency Graph](#7-dependency-graph)
8. [Currency & Player State](#8-currency--player-state)
9. [Default Actions](#9-default-actions)
10. [Save System](#10-save-system)
11. [UI Architecture](#11-ui-architecture)

---

## 1. Project Structure

```
deep-state/
├── assets/                          # Data files (.tres resources)
│   ├── events/                      # (Reserved for future event data)
│   ├── institutions/                # Institution configuration files
│   │   ├── govt_novara.tres         # Government institution config
│   │   ├── intel_novara.tres        # Intelligence agency config
│   │   ├── media_novara.tres        # Media institution config
│   │   └── military_novara.tres     # Military institution config
│   └── regions/
│       └── novara.tres              # Region configuration (institutions, dependencies, crisis tree)
│
├── scenes/                          # Godot scene files (.tscn)
│   ├── menu/
│   │   ├── event_tree_viewer.tscn   # Debug tree visualization
│   │   └── main_menu.tscn           # Main menu scene
│   ├── simulation/
│   │   ├── crisis_overlay.tscn      # Crisis popup overlay
│   │   ├── game_over.tscn           # Game over screen
│   │   ├── institution_card.tscn    # UI card for each institution
│   │   └── simulation.tscn          # MAIN GAME SCENE
│   └── world/
│       └── world_map.tscn           # World map (future use)
│
├── src/                             # GDScript source code
│   ├── core/                        # Core game state
│   │   ├── player_state.gd          # Player currencies (cash, bandwidth, exposure)
│   │   └── world_context.gd         # World/region context
│   │
│   ├── data/                        # Data structures & configs
│   │   ├── institution_config.gd    # InstitutionConfig class definition
│   │   ├── region_config.gd         # RegionConfig class definition
│   │   ├── region_save_state.gd     # Save state management
│   │   └── save_game.gd             # Save/load utilities
│   │
│   ├── events/
│   │   └── event_manager.gd         # Event resolution, queuing, default actions
│   │
│   ├── simulation/                  # Core simulation systems
│   │   ├── dependency_graph.gd      # Institution dependency network
│   │   ├── institution.gd           # Institution class (stress, capacity, etc.)
│   │   ├── institution_manager.gd   # Manages all institutions
│   │   ├── simulation_clock.gd      # Day tracking
│   │   ├── simulation_root.gd       # MAIN ORCHESTRATOR - ties everything together
│   │   └── tension_manager.gd       # Global tension & crisis threshold
│   │
│   └── ui/                          # UI controllers
│       ├── event_tree_viewer.gd     # Tree visualization logic
│       ├── main_menu.gd             # Menu logic
│       └── world_map.gd             # Map logic
│
└── saved-games/                     # Save files directory
```

---

## 2. Core Game Loop

### Main Orchestrator: `simulation_root.gd`

The game runs on a **day-based turn system**. Here's the complete flow:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GAME INITIALIZATION                              │
├─────────────────────────────────────────────────────────────────────────┤
│ 1. Load RegionConfig from novara.tres                                    │
│ 2. Create institutions from InstitutionConfig files                      │
│ 3. Build dependency graph from initial_dependencies                      │
│ 4. Initialize save state                                                 │
│ 5. Wire up all managers (event_manager, tension_mgr, etc.)              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         DAY N START                                      │
├─────────────────────────────────────────────────────────────────────────┤
│ Step 0: Apply DELAYED EFFECTS from yesterday's choices                   │
│         (queued_effects array → apply to institutions)                   │
│                                                                          │
│ Step 1: Daily institution updates                                        │
│         - daily_auto_update(): strength += capacity * regen_rate         │
│         - apply_stress_decay(): stress -= stress * 5% (percentage decay) │
│                                                                          │
│ Step 2: Collect day start events                                         │
│         - Check stress_triggered_tree (stress >= strength)               │
│         - Check randomly_triggered_tree (probability based on capacity)  │
│         - Check crisis_tree (tension >= threshold)                       │
│         - Apply BASE EFFECTS immediately                                 │
│         - Add to pending_events queue                                    │
│                                                                          │
│ Step 3: End of day updates                                               │
│         - decay_exposure() on player                                     │
│         - Increment day counter                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         PLAYER PHASE                                     │
├─────────────────────────────────────────────────────────────────────────┤
│ Player can:                                                              │
│ - Respond to pending events (make choices)                               │
│ - Execute default actions on institutions                                │
│ - Add tension (debug button)                                             │
│ - View crisis status                                                     │
│ - Advance to next day                                                    │
│                                                                          │
│ When responding to events:                                               │
│ - COST is spent immediately                                              │
│ - CHOICE EFFECTS are queued for next day                                 │
│ - INFLUENCE changes based on choice                                      │
│ - Tree state updates (next_node, prune branches)                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    CRISIS CHECK (on tension increase)                    │
├─────────────────────────────────────────────────────────────────────────┤
│ If tension >= threshold (100):                                           │
│ 1. Find epicenter (highest stress institution)                           │
│ 2. Print graph BEFORE crisis                                             │
│ 3. Apply crisis effects to dependency graph (distance-based)             │
│ 4. Propagate stress from epicenter                                       │
│ 5. Print graph AFTER crisis effects                                      │
│ 6. Show EMERGENCY POPUP with choices                                     │
│ 7. On choice: apply randomized effects (±30%), rewire for resilience    │
│ 8. Print graph AFTER resolution                                          │
│ 9. Reset tension to 30%                                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Architecture

### Class vs Resource Pattern

The game uses Godot's **Resource system** to separate logic from data:

| File Type          | Purpose                             | Example                                                 |
| ------------------ | ----------------------------------- | ------------------------------------------------------- |
| `.gd` (class_name) | Defines structure, methods, signals | `institution_config.gd` defines InstitutionConfig class |
| `.tres` (resource) | Stores actual data instances        | `govt_novara.tres` contains Government's event trees    |

### RegionConfig (`region_config.gd` → `novara.tres`)

```gdscript
class_name RegionConfig extends Resource

@export var region_id: String                    # "novara"
@export var region_name: String                  # "Republic of Novara"
@export var institution_config_paths: Dictionary # { "govt_novara": "res://assets/..." }
@export var initial_dependencies: Dictionary     # Graph edges with weights
@export var currencies: Dictionary               # Initial currency values
@export var crisis_tree: Array                   # Global crisis event tree
```

### InstitutionConfig (`institution_config.gd` → `govt_novara.tres`)

```gdscript
class_name InstitutionConfig extends Resource

@export var institution_id: String
@export var institution_name: String
@export var institution_type: Institution.InstitutionType  # MILITANT, CIVILIAN, POLICY, INTELLIGENCE
@export var initial_capacity: float
@export var initial_strength: float
@export var initial_stress: float
@export var initial_influence: float

# Event Trees
@export var stress_triggered_tree: Array    # Events when stress >= strength
@export var randomly_triggered_tree: Array  # Events based on probability
```

---

## 4. Institution System

### Institution Class (`institution.gd`)

Each institution has these core stats:

| Stat               | Range | Description                             |
| ------------------ | ----- | --------------------------------------- |
| `capacity`         | 0-100 | Resource generation capability          |
| `strength`         | 0-100 | Resistance to stress (stress threshold) |
| `stress`           | 0-200 | Current pressure on institution         |
| `player_influence` | 0-100 | Player's control over institution       |

### Institution Types

```gdscript
enum InstitutionType { MILITANT, CIVILIAN, POLICY, INTELLIGENCE }
```

Each type has different default actions available.

### Daily Updates

```gdscript
func daily_auto_update() -> void:
    # Strength regenerates based on capacity
    strength = min(strength + (capacity * capacity_regeneration / 100.0), 100.0)

func apply_stress_decay() -> void:
    # Stress decays by 5% per day (percentage-based)
    var decay_amount = stress * stress_decay_rate  # 0.05
    reduce_stress(decay_amount)
```

### Signals

```gdscript
signal stress_changed(new_stress: float)
signal capacity_changed(new_capacity: float)
signal influence_changed(new_influence: float)
signal strength_changed(new_strength: float)
signal stress_maxed_out()  # Emitted when stress >= 100
```

---

## 5. Event System

### Event Manager (`event_manager.gd`)

Handles all event logic: collection, queuing, resolution.

### Event Types

```gdscript
enum EventType { STRESS, RANDOM, CRISIS }
```

| Type   | Trigger Condition                            | Source                                         |
| ------ | -------------------------------------------- | ---------------------------------------------- |
| STRESS | `institution.stress >= institution.strength` | `stress_triggered_tree` in InstitutionConfig   |
| RANDOM | Probability based on capacity                | `randomly_triggered_tree` in InstitutionConfig |
| CRISIS | `tension >= threshold` (100)                 | `crisis_tree` in RegionConfig                  |

### Event Tree Structure

Each event node in a tree has this structure:

```gdscript
{
    "node_id": "unique_event_id",
    "title": "Event Title",
    "description": "What happened...",
    "conditions": {                    # Optional: when this node can trigger
        "min_stress": 50.0,
        "min_influence": 20.0
    },
    "effects": {                       # Base effects (applied IMMEDIATELY when event triggers)
        "stress": 10,
        "capacity": -5
    },
    "choices": [
        {
            "text": "Choice text shown to player",
            "description": "Detailed description",
            "cost": { "bandwidth": 10, "cash": 50 },     # Paid IMMEDIATELY on selection
            "effects": { "stress": -20, "strength": 5 }, # Applied NEXT DAY (delayed)
            "next_node": "follow_up_event_id",          # Next event in tree
            "prunes_branches": ["alternative_event_id"]  # Blocks these events permanently
        }
    ]
}
```

### Event Queues

| Queue                   | Type       | Purpose                                    |
| ----------------------- | ---------- | ------------------------------------------ |
| `pending_events`        | Dictionary | Regular events waiting for player response |
| `pending_crisis_events` | Array      | Crisis events (separate, higher priority)  |
| `queued_effects`        | Array      | Effects from choices, applied next day     |
| `event_history`         | Array      | Record of all resolved events              |

### Event Flow Timeline

```
┌─────────────────────────────────────────────────────────────────┐
│ EVENT TRIGGERS (Day Start)                                       │
├─────────────────────────────────────────────────────────────────┤
│ 1. Check trigger conditions (stress >= strength, probability)    │
│ 2. Apply BASE EFFECTS immediately to institution                 │
│ 3. Calculate and apply EXPOSURE increase                         │
│ 4. Apply AUTONOMOUS probabilistic effects (based on capacity)    │
│ 5. Add to pending_events queue                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ PLAYER RESPONDS (During Player Phase)                            │
├─────────────────────────────────────────────────────────────────┤
│ 1. Player selects a choice                                       │
│ 2. COST is spent immediately (cash, bandwidth)                   │
│ 3. CHOICE EFFECTS are QUEUED for next day                        │
│ 4. INFLUENCE changes based on choice aggressiveness              │
│ 5. Tree state updates:                                           │
│    - current_node → choice.next_node                             │
│    - prunes_branches added to pruned list                        │
│ 6. Event removed from pending queue                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ NEXT DAY START                                                   │
├─────────────────────────────────────────────────────────────────┤
│ 1. Apply all queued_effects from yesterday's choices             │
│ 2. Clear queued_effects array                                    │
│ 3. Continue with new day collection...                           │
└─────────────────────────────────────────────────────────────────┘
```

### Exposure Calculation

```gdscript
func calculate_event_exposure(institution: Institution, base_exposure: float = 5.0) -> float:
    var stress_factor = institution.stress / 100.0
    var influence_factor = institution.player_influence / 100.0
    var strength_factor = institution.strength / 200.0
    var current_exposure_factor = 1.0 + (player_state.exposure / 100.0)

    # Higher stress + influence = more exposure, higher strength = less
    return base_exposure * (stress_factor + influence_factor - strength_factor) * current_exposure_factor
```

### Autonomous Effects (Probabilistic)

When events trigger, random buffs/debuffs are applied based on capacity:

```gdscript
var effect_probability = (100.0 - institution.capacity) / 100.0
# Lower capacity = higher chance of negative effects

if randf() < effect_probability:
    # Apply stress increase
if randf() < effect_probability * 0.5:
    # Apply strength decrease
if randf() < effect_probability * 0.7:
    # Apply exposure increase
```

---

## 6. Crisis System

### Tension Manager (`tension_manager.gd`)

```gdscript
const CRISIS_THRESHOLD: float = 100.0
const TENSION_RESET_FACTOR: float = 0.3  # Reset to 30% after crisis

var global_tension: float = 0.0
```

### Crisis Trigger Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ TENSION REACHES THRESHOLD (100)                                  │
├─────────────────────────────────────────────────────────────────┤
│ Auto-triggered when player adds tension or events increase it    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ FIND EPICENTER                                                   │
├─────────────────────────────────────────────────────────────────┤
│ Institution with highest stress becomes the crisis epicenter     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ IMMEDIATELY AFFECT GLOBAL GRAPH                                  │
├─────────────────────────────────────────────────────────────────┤
│ apply_crisis_effects() - rewire based on distance from epicenter │
│ propagate_stress() - spread stress through edges                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ SHOW EMERGENCY POPUP                                             │
├─────────────────────────────────────────────────────────────────┤
│ Player must respond with one of the crisis choices               │
│ Effects shown with randomness range (±30%)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ APPLY RANDOMIZED EFFECTS                                         │
├─────────────────────────────────────────────────────────────────┤
│ Each effect value has ±30% variance                              │
│ Affects: tension, exposure, influence, stress, capacity          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ POST-CRISIS                                                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. Prune unchosen crisis branches                                │
│ 2. Reset tension to 30%                                          │
│ 3. rewire_for_resilience() - institutions adapt                  │
│ 4. Print final graph state                                       │
└─────────────────────────────────────────────────────────────────┘
```

### Crisis Tree Structure (in RegionConfig)

```gdscript
crisis_tree = [
    {
        "node_id": "crisis_constitutional",
        "title": "Constitutional Crisis",
        "description": "...",
        "conditions": { "tension_threshold": 80.0 },
        "effects": { },  # Base effects applied immediately
        "choices": [
            {
                "text": "Support Executive Power",
                "requires": { "min_govt_influence": 40.0 },
                "cost": { "cash": 1500.0, "bandwidth": 35.0 },
                "effects": {
                    "tension_change": -45.0,      # These have ±30% randomness
                    "exposure_change": 18.0,
                    "govt_influence_change": 15.0
                },
                "next_node": "crisis_executive_win"
            }
        ]
    }
]
```

---

## 7. Dependency Graph

### Graph Structure (`dependency_graph.gd`)

```gdscript
# Adjacency list: source_id -> { target_id: weight }
var edges: Dictionary = {
    "govt_novara": { "military_novara": 0.8, "media_novara": 0.6 },
    "military_novara": { "intel_novara": 0.75 },
    ...
}
```

### Edge Weights

- **Range**: 0.0 to 1.0
- **Meaning**: How much stress propagates from source to target
- **Higher weight** = stronger dependency = more stress spread

### Crisis Graph Rewiring (Distance-Based)

When crisis triggers, edges are modified based on distance from epicenter:

```
                    EPICENTER
            stress_ratio = stress / strength
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
    [Level 1]       [Level 1]       [Level 1]
    +0.5 × ratio    +0.5 × ratio    +0.5 × ratio
         │               │
         ▼               ▼
    [Level 2]       [Level 2]
    +0.25 × ratio   +0.25 × ratio
         │
         ▼
    [Level 3+]
    No effect
```

```gdscript
func apply_crisis_effects(crisis_effects: Dictionary, inst_manager: InstitutionManager):
    var stress_ratio = epicenter.stress / epicenter.strength
    var level_1_multiplier = 0.5 * stress_ratio   # Adjacent to epicenter
    var level_2_multiplier = 0.25 * stress_ratio  # 2nd level
    # Level 3+: no effect
```

### Stress Propagation

```gdscript
func propagate_stress(source_inst: Institution, inst_manager: InstitutionManager):
    for target_id in edges[source_id]:
        var weight = edges[source_id][target_id]
        var propagated_stress = source_inst.stress * weight * 0.1  # 10% * weight
        target.apply_stress(propagated_stress)
```

### Resilience Rewiring (Post-Crisis)

After crisis resolves, institutions adapt:

```gdscript
func rewire_for_resilience(inst_manager: InstitutionManager):
    for each edge:
        if target.stress_ratio > 0.3:
            # Reduce weight to stressed institutions
            weight -= 0.1 * stress_ratio
        elif target.stress_ratio < 0.2:
            # Increase weight to stable institutions
            weight += 0.05 * (1.0 - stress_ratio)
```

### Graph Printing

```
╔══════════════════════════════════════════════════════════════╗
║ GRAPH AFTER CRISIS EFFECTS
║ Change originated from: military_novara
╠══════════════════════════════════════════════════════════════╣
║ govt_novara  → military_nov: 0.950 [█████████░]
║ govt_novara  → media_novara: 0.600 [██████░░░░]
║ military_nov → intel_novara: 0.860 [████████░░]
╚══════════════════════════════════════════════════════════════╝
```

---

## 8. Currency & Player State

### Player State (`player_state.gd`)

| Currency    | Initial | Max    | Description                   |
| ----------- | ------- | ------ | ----------------------------- |
| `cash`      | 1000    | 999999 | Money for operations          |
| `bandwidth` | 50      | 100    | Operational capacity          |
| `exposure`  | 0       | 100    | How visible the Deep State is |

### Exposure Mechanics

- **Increases**: From events, aggressive actions, crisis choices
- **Decreases**: Daily decay (0.5 per day), some actions
- **Impact**: Higher exposure = lower relevance during crisis

### Relevance Calculation

```gdscript
func calculate_relevance(institutions: Array) -> float:
    var influence_factor = total_influence / max_possible_influence
    var exposure_factor = exposure / 100.0

    # Relevance = 70% influence + 30% exposure (weighted)
    return (influence_factor * 0.7 + exposure_factor * 0.3) * 100.0
```

**Relevance < 30%** during crisis = **GAME OVER**

---

## 9. Default Actions

### Action System

Each institution type has **5 default actions** unlocked at influence thresholds:

| Threshold | Unlock Level                    |
| --------- | ------------------------------- |
| 0         | Basic action (always available) |
| 20        | Tier 2 action                   |
| 40        | Tier 3 action                   |
| 60        | Tier 4 action                   |
| 80        | Tier 5 action (most powerful)   |

### Action Structure

```gdscript
{
    "id": "mil_gather_intel",
    "title": "Gather Intelligence",
    "description": "Use contacts to collect military intelligence.",
    "effects": { "stress": 5 },           # Applied to institution
    "influence_change": 3,                 # Player gains influence
    "cost": { "bandwidth": 5 },            # Player pays this
    "required_influence": 0                # Unlock threshold
}
```

### Action Effects

**All default actions:**

- **INCREASE stress** on the institution (destabilizing)
- **INCREASE influence** on the institution (player gains control)
- **Cost bandwidth/cash** (player resources)

This creates the core gameplay loop:

1. Spend resources to destabilize institutions
2. Gain influence as you destabilize
3. Higher influence unlocks more powerful actions
4. More stress can trigger events

### Actions by Institution Type

#### MILITANT

| Level | Action                    | Stress | Influence | Cost        |
| ----- | ------------------------- | ------ | --------- | ----------- |
| 0     | Gather Intelligence       | +5     | +3        | 5 BW        |
| 20    | Supply Operations         | +10    | +5        | 10 BW, $50  |
| 40    | Cultivate Officer Network | +15    | +8        | 15 BW, $100 |
| 60    | Strategic Leak            | +25    | +10       | 20 BW       |
| 80    | Support Coup Faction      | +40    | +15       | 30 BW, $200 |

#### CIVILIAN

| Level | Action               | Stress | Influence | Cost        |
| ----- | -------------------- | ------ | --------- | ----------- |
| 0     | Community Outreach   | +5     | +3        | 5 BW        |
| 20    | Media Campaign       | +12    | +5        | 10 BW, $30  |
| 40    | Organize Protests    | +20    | +8        | 15 BW       |
| 60    | General Strike       | +30    | +10       | 25 BW, $100 |
| 80    | Trigger Civil Unrest | +45    | +15       | 30 BW, $150 |

#### POLICY

| Level | Action                | Stress | Influence | Cost        |
| ----- | --------------------- | ------ | --------- | ----------- |
| 0     | Submit Policy Brief   | +5     | +3        | 5 BW        |
| 20    | Lobby Officials       | +10    | +5        | 10 BW, $80  |
| 40    | Expose Scandal        | +18    | +8        | 15 BW       |
| 60    | Sabotage Policy       | +28    | +10       | 20 BW, $120 |
| 80    | Trigger Regime Crisis | +40    | +15       | 30 BW, $200 |

#### INTELLIGENCE

| Level | Action                  | Stress | Influence | Cost        |
| ----- | ----------------------- | ------ | --------- | ----------- |
| 0     | Plant Asset             | +6     | +3        | 8 BW        |
| 20    | Counter-Intelligence Op | +12    | +5        | 12 BW       |
| 40    | Data Breach             | +22    | +8        | 18 BW       |
| 60    | Turn Double Agent       | +30    | +12       | 25 BW, $150 |
| 80    | Trigger Agency Collapse | +45    | +15       | 35 BW, $200 |

---

## 10. Save System

### Save State (`region_save_state.gd`)

```gdscript
class_name RegionSaveState extends Resource

@export var region_id: String
@export var current_day: int
@export var is_lost: bool
@export var high_score: int
@export var currencies: Dictionary          # { "cash": 1000, "bandwidth": 50, ... }
@export var crisis_tree_state: Dictionary   # { "current_node": "", "pruned_branches": [] }
@export var institutions: Dictionary        # Per-institution state
@export var global_tension: float
```

### Institution State in Save

```gdscript
institutions[inst_id] = {
    "capacity": 50.0,
    "strength": 100.0,
    "stress": 0.0,
    "influence": 0.0,
    "stress_tree_state": {
        "current_node": "",           # Current position in tree
        "pruned_branches": []         # Blocked event nodes
    },
    "random_tree_state": {
        "current_node": "",
        "pruned_branches": []
    }
}
```

### Tree State Tracking

When player makes a choice:

1. `current_node` updates to `choice.next_node`
2. `prunes_branches` from choice are added to `pruned_branches`
3. Pruned nodes can never trigger again

### Save/Load

```gdscript
# Quick save (F5)
func quick_save():
    save_state.save_to_file(region_config.region_id)

# Quick load (F9)
func quick_load():
    var loaded = RegionSaveState.load_from_file(region_id)
    load_save_state(loaded)
```

---

## 11. UI Architecture

### Main Simulation Scene (`simulation.tscn`)

```
SimulationRoot (Node2D)
└── SimulationUI (CanvasLayer)
    ├── MainLayout (PanelContainer)
    │   └── MarginContainer
    │       └── MainVBox
    │           ├── PlayerDashboard      # Day, Cash, Bandwidth, Exposure, Tension
    │           ├── ContentHSplit
    │           │   ├── LeftPanel
    │           │   │   └── InstitutionPanel  # Institution cards
    │           │   └── RightPanel
    │           │       ├── TreeTypeHBox      # Institution & tree type selectors
    │           │       ├── EventTreePanel    # Event tree visualization
    │           │       └── DefaultActionsPanel  # Default actions UI
    │           └── DebugPanel            # Debug buttons
    │
    ├── EventDialog (ColorRect)           # Event choice popup
    ├── CrisisOverlay (ColorRect)         # Crisis emergency popup
    ├── EventQueueOverlay (ColorRect)     # Event queue view
    ├── CrisisViewOverlay (ColorRect)     # Crisis status view
    └── PauseMenu (ColorRect)             # Pause/save menu
```

### Institution Card (`institution_card.tscn`)

Displays:

- Institution name and type
- Capacity bar
- Strength bar
- Stress bar (changes color based on ratio)
- Influence bar

### Event Tree Visualization

Tree view shows:

- ✓ Current/visited nodes (green)
- ✗ Pruned nodes (red)
- ○ Available nodes
- Choices under each node

---

## Quick Reference: Key Functions

### simulation_root.gd

| Function                             | Purpose                          |
| ------------------------------------ | -------------------------------- |
| `_on_debug_advance_day()`            | Main day advancement logic       |
| `_auto_trigger_crisis()`             | Crisis trigger and graph effects |
| `_on_emergency_crisis_choice()`      | Handle crisis resolution         |
| `_apply_randomized_crisis_effects()` | Apply ±30% variance effects      |

### event_manager.gd

| Function                     | Purpose                          |
| ---------------------------- | -------------------------------- |
| `collect_day_start_events()` | Gather all triggered events      |
| `resolve_event()`            | Process player's event choice    |
| `get_default_actions()`      | Get 5 actions for institution    |
| `execute_default_action()`   | Run a default action             |
| `queue_delayed_effects()`    | Queue effects for next day       |
| `apply_queued_effects()`     | Apply yesterday's queued effects |

### dependency_graph.gd

| Function                  | Purpose                      |
| ------------------------- | ---------------------------- |
| `apply_crisis_effects()`  | Distance-based edge rewiring |
| `propagate_stress()`      | Spread stress through edges  |
| `rewire_for_resilience()` | Post-crisis adaptation       |
| `print_graph_weights()`   | Debug output of all edges    |

### institution.gd

| Function               | Purpose                                |
| ---------------------- | -------------------------------------- |
| `apply_stress()`       | Add stress (may emit stress_maxed_out) |
| `daily_auto_update()`  | Strength regeneration                  |
| `apply_stress_decay()` | 5% stress decay per day                |
| `increase_influence()` | Modify player influence                |

---

## Game Balance Summary

| Mechanic                 | Value                 | Notes                |
| ------------------------ | --------------------- | -------------------- |
| Stress decay             | 5% per day            | Percentage-based     |
| Strength regen           | capacity × 2% per day | Based on capacity    |
| Exposure decay           | 0.5 per day           | Flat decay           |
| Crisis threshold         | 100 tension           | Auto-triggers        |
| Crisis reset             | 30% of tension        | After resolution     |
| Default action stress    | +5 to +45             | Increases with level |
| Default action influence | +3 to +15             | Increases with level |
| Game over                | Relevance < 30%       | During crisis        |
| Graph L1 multiplier      | 0.5 × stress_ratio    | Adjacent edges       |
| Graph L2 multiplier      | 0.25 × stress_ratio   | Second level         |
| Effect randomness        | ±30%                  | Crisis choices only  |
