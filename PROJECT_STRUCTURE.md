## Project structure documentation

## Deep State - Systemic Strategy Game

# Directory Organization

## /src - Game source code

### /core

- world_context.gd - Static context layer (immutable region setup)
- player_state.gd - Player resources (cash, bandwidth, exposure)

### /simulation

- institution.gd - Individual institution agent
- institution_manager.gd - Institution ownership and management
- dependency_graph.gd - Institutional dependency network
- tension_manager.gd - Global tension tracking
- simulation_clock.gd - Daily cycle orchestration
- simulation_root.gd - Main simulation coordinator

### /events

- event_manager.gd - Event triggering and effect application

### /ui

- main_menu.gd - Main menu controller

### /data

- region_config.gd - Region templates and setup
- save_game.gd - Game state serialization

## /scenes - Godot scene files

### /menu

- main_menu.tscn - Main menu scene

### /world

- world_map.tscn - Region selection map
- region_info_panel.tscn - Region info display

### /simulation

- simulation_ui.tscn - Main simulation UI
- institution_panel.tscn - Institution display
- player_dashboard.tscn - Player resources display
- event_dialog.tscn - Event presentation

## /assets - Game assets

### /regions

- Region configuration resources (.tres)

### /events

- Event tree resources (.tres)

## Core Architecture

### Layered Design (Section 2 of logic.txt)

1. **Static Context Layer** - Immutable region setup
2. **Institutional Layer** - Semi-autonomous agents
3. **Dependency Graph** - Institution connections
4. **Player State** - Deep State resources
5. **Event System** - Change propagation
6. **Daily Simulation** - Strict execution order

### Daily Cycle Order (Section 4 of logic.txt)

1. Day Start
2. Institutions auto-update
3. Minor events triggered
4. Global tension updated
5. Crisis check
6. Player turn
7. Day End

### Key Design Patterns

- No direct manipulation - all effects through events
- Deterministic institution behavior
- Probabilistic stable events
- Stress-triggered crises
- Relevance-based game over

## Development Checklist

- [ ] Implement event tree system
- [ ] Create region configs for test regions
- [ ] Build world map UI with region selection
- [ ] Implement main simulation UI
- [ ] Create action system for player input
- [ ] Implement event outcome system
- [ ] Add save/load functionality
- [ ] Build crisis evaluation
- [ ] Create game over sequences
- [ ] Add visual feedback for tension/stress
- [ ] Implement audio system
- [ ] Add difficulty/modifiers
