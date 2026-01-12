## Scene Structure Documentation

# Scene Hierarchy

## res://scenes/menu/main_menu.tscn

**Root**: MainMenu (Control)
**Script**: src/ui/main_menu.gd
**Children**:

- VBoxContainer
  - TitleLabel (text: "DEEP STATE")
  - PlayButton (signal: pressed → \_on_play_pressed)
  - QuitButton (signal: pressed → \_on_quit_pressed)

**Purpose**: Entry point for the game, allows player to start a new game or quit.

---

## res://scenes/world/world_map.tscn

**Root**: WorldMap (Control)
**Script**: src/ui/world_map.gd
**Children**:

- TitleLabel (anchors top, 10% height)
- RegionContainer (VBoxContainer, 20%-90%)
  - [Dynamically populated with region buttons]
- RegionInfoPanel (PanelContainer, bottom 15%)
  - VBoxContainer
    - RegionName (Label)
    - RegionDescription (Label)
    - RegionStats (Label)
    - StartButton (disabled until region selected)

**Purpose**: Region selection interface. Displays available regions and loads the selected region into the simulation.

---

## res://scenes/simulation/simulation.tscn

**Root**: SimulationRoot (Node2D)
**Script**: src/simulation/simulation_root.gd
**Purpose**: Main game simulation orchestrator

**Core Systems** (children):

- WorldContext (Node) - Read-only region context
- PlayerState (Node) - Cash, bandwidth, exposure tracking
- InstitutionManager (Node) - Institution ownership
- DependencyGraph (Node) - Institution dependency network
- TensionManager (Node) - Global tension tracking
- EventManager (Node) - Event triggering and effects
- SimulationClock (Node) - Daily cycle enforcement

**UI Layer** (SimulationUI - CanvasLayer):

- PlayerDashboard (Control, top 10%)

  - VBoxContainer
    - HBoxContainer
      - DayLabel
      - CashLabel
      - BandwidthLabel
      - ExposureLabel
    - TensionBar (ProgressBar)

- InstitutionPanel (Control, 10%-90%)

  - ScrollContainer
    - VBoxContainer (dynamically populated with institution cards)

- EventDialog (Control, initially hidden)

  - PanelContainer (centered 25%-75%)
    - VBoxContainer
      - TitleLabel
      - DescriptionLabel
      - ChoicesContainer (VBoxContainer for choice buttons)

- CrisisOverlay (Control, initially hidden)
  - ColorRect (semi-transparent black)
  - CrisisPanel (PanelContainer, centered 20%-80%)
    - VBoxContainer
      - CrisisTitle
      - CrisisDescription

**Purpose**: Complete simulation environment with UI for institution management, resource tracking, events, and crises.

---

## res://scenes/simulation/institution_card.tscn

**Root**: InstitutionCard (PanelContainer)
**Script**: scenes/simulation/institution_card.gd
**Custom Minimum Size**: 300x150
**Children**:

- MarginContainer (10px margins)
  - VBoxContainer
    - HeaderHBox
      - InstitutionName (Label, 16pt)
      - InstitutionType (Label, right-aligned)
    - StatsContainer (GridContainer, 2 columns)
      - CapacityLabel / CapacityBar
      - StrengthLabel / StrengthBar
      - StressLabel / StressBar
      - InfluenceLabel / InfluenceBar
    - ActionsHBox (HBoxContainer, center-aligned)
      - [Dynamically populated with action buttons]

**Purpose**: Reusable card component for displaying individual institution stats and available actions.

---

## res://scenes/simulation/game_over.tscn

**Root**: GameOverScreen (Control)
**Script**: scenes/simulation/game_over.gd
**Children**:

- ColorRect (dark overlay, 80% opacity)
- CenterContainer
  - VBoxContainer
    - TitleLabel (text: "The Deep State Lost Relevance")
    - ScoreLabel (text: "Days Survived: X")
    - ReasonLabel (wrapped text)
    - HighScoreLabel (text: "Best: X days")
    - ButtonHBox
      - RetryButton (signal: pressed → \_on_retry_pressed)
      - MenuButton (signal: pressed → \_on_menu_pressed)

**Purpose**: Display when player loses, shows final score and allows retry or return to menu.

---

# Node-to-Script Mapping

| Scene                 | Root Node       | Script                                | Parent Class   |
| --------------------- | --------------- | ------------------------------------- | -------------- |
| main_menu.tscn        | MainMenu        | src/ui/main_menu.gd                   | Control        |
| world_map.tscn        | WorldMap        | src/ui/world_map.gd                   | Control        |
| simulation.tscn       | SimulationRoot  | src/simulation/simulation_root.gd     | Node2D         |
| institution_card.tscn | InstitutionCard | scenes/simulation/institution_card.gd | PanelContainer |
| game_over.tscn        | GameOverScreen  | scenes/simulation/game_over.gd        | Control        |

---

# Signal Connections

## main_menu.tscn

```
PlayButton.pressed → MainMenu._on_play_pressed()
QuitButton.pressed → MainMenu._on_quit_pressed()
```

## world_map.tscn

```
[Region Buttons].pressed → WorldMap._on_region_selected(region_id)
StartButton.pressed → WorldMap._on_start_pressed()
```

## simulation.tscn

```
TensionManager.crisis_triggered → SimulationRoot._on_crisis(epicenter)
SimulationClock.crisis_phase → SimulationRoot._handle_crisis_phase()
SimulationClock.player_turn_phase → SimulationRoot._handle_player_turn_phase()
Institution.stress_changed → [UI updates]
Institution.influence_changed → [UI updates]
PlayerState.cash_changed → [Dashboard updates]
PlayerState.exposure_changed → [Dashboard updates]
```

## institution_card.tscn

```
Institution.stress_changed → InstitutionCard._on_stress_changed()
Institution.capacity_changed → InstitutionCard._on_capacity_changed()
Institution.strength_changed → InstitutionCard._on_strength_changed()
Institution.influence_changed → InstitutionCard._on_influence_changed()
[Action Buttons].pressed → InstitutionCard._on_action_pressed(action_name)
```

## game_over.tscn

```
RetryButton.pressed → GameOverScreen._on_retry_pressed()
MenuButton.pressed → GameOverScreen._on_menu_pressed()
```

---

# Data Flow

## Game Startup

1. main_menu.tscn → PlayButton pressed
2. Load world_map.tscn
3. world_map loads available region configs
4. Player selects region → StartButton pressed
5. Create SimulationRoot with selected RegionConfig
6. Load simulation.tscn
7. SimulationRoot.initialize_region(config)
8. Create institutions from config templates
9. Build dependency graph from config
10. Display institutions via InstitutionCard components

## Daily Cycle

1. SimulationClock.advance_day() called
2. WorldContext → day start signal
3. InstitutionManager.daily_update()
   - Each institution: auto-update strength, apply stress decay
4. EventManager: trigger stress/stable events
5. TensionManager: update global tension
6. Check if crisis threshold exceeded
   - If yes: crisis phase → relevance evaluation
   - If no: continue
7. SimulationClock: player turn phase (wait for input)
8. PlayerState.decay_exposure()
9. Day incremented

## Crisis Resolution

1. TensionManager detects tension >= threshold
2. Get epicenter institution (highest stress)
3. Calculate Deep State relevance:
   - influence_score = avg(institution.player_influence / 100)
   - exposure_penalty = player_exposure \* 0.5
   - relevance = influence_score - exposure_penalty
4. If relevance < 0.3:
   - Game over (load game_over.tscn)
5. Else:
   - Reset tension
   - Dependency graph rewires for resilience

---

# Key Implementation Notes

## Scene Lifecycle

- Main menu is NOT persistent across scenes
- World map is NOT persistent
- Simulation systems ARE persistent during play
- Game over screen overlays simulation (not a new scene)

## Dynamic UI

- Institution cards are instantiated from institution_card.tscn
- Action buttons are created dynamically based on player influence
- Event dialog choices are generated from event trees
- Crisis panel content varies by epicenter institution

## State Management

- SimulationRoot owns all simulation systems
- PlayerState, Institution, DependencyGraph are children of SimulationRoot
- All save/load operations go through SimulationRoot.save_game()
- UI systems reference simulation systems as needed

## Future Expansions

- Event tree resource system (partial implementation in EventManager)
- Dialog system for event outcomes
- More sophisticated crisis evaluation
- Visual effects for stress/tension
- Sound design system
