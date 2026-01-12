## Debug & Test Features

This document describes the test buttons and debug features available in the simulation.

### Debug Panel Location

The debug panel appears at the bottom of the simulation screen (bottom 10% of screen).

### Available Test Buttons

#### Game Flow

- **Advance Day** - Manually advance to the next day
  - Updates institution auto-recovery
  - Applies stress decay
  - Decrements exposure
  - Increments day counter
  - Updates dashboard display

#### Institution Mechanics

- **Add Stress** - Adds 20 stress to a random institution

  - Useful for testing stress-triggered events
  - Helps verify stress UI feedback
  - Can push institutions toward crisis behavior

- **Add Influence** - Adds 15 influence to a random institution
  - Tests influence tier unlocking
  - Verifies action button availability
  - Used for testing Deep State relevance

#### Tension & Crisis System

- **Add Tension** - Increases global tension by 10

  - Tests tension progression toward crisis
  - Verifies tension bar display
  - Useful for rapid crisis testing
  - Tension threshold is 100.0

- **Trigger Crisis** - Immediately evaluates crisis
  - Finds institution with highest stress (epicenter)
  - Calculates Deep State relevance
  - Tests loss condition if relevance < 0.3
  - Otherwise resets tension and rewires dependencies

#### Player Resources

- **Add Cash** - Adds $500 to player resources

  - Tests cash display
  - Verifies resource UI updates
  - Used for testing action costs

- **Add Bandwidth** - Adds 25 bandwidth (max 100)
  - Tests bandwidth capping
  - Verifies bandwidth display
  - Used for action availability testing

#### Events

- **Test Event** - Triggers a test event on a random institution
  - Effects applied:
    - Stress: -15 (reduce stress)
    - Cash: +100
    - Exposure: +10
    - Tension: +5
  - Tests event effect propagation
  - Verifies dashboard updates

### Test Scenarios

#### Scenario 1: Basic Simulation

1. Click "Advance Day" several times
2. Observe institution stats update
3. Check day counter increases
4. Verify exposure decays

#### Scenario 2: Stress & Events

1. Click "Add Stress" multiple times on same institution
2. Watch stress bar fill (red coloring appears)
3. Click "Test Event" to see effects propagate
4. Verify cash and tension update

#### Scenario 3: Influence Progression

1. Click "Add Influence" 3+ times on same institution
2. Institution card should show more action buttons
3. Action buttons unlock at:
   - 10+ influence: light_pressure
   - 30+ influence: moderate_pressure
   - 60+ influence: heavy_pressure
   - 80+ influence: deep_action

#### Scenario 4: Crisis Trigger

1. Click "Add Tension" until tension bar is ~90-100%
2. Click "Trigger Crisis" button
3. If influence spread is good, crisis resolves and tension resets
4. If influence is concentrated, relevance < 0.3 triggers game over

#### Scenario 5: Resource Management

1. Click "Add Cash" and "Add Bandwidth"
2. Verify dashboard labels update immediately
3. Test that resources are used by actions (when implemented)

### Test Region Setup

The test region is automatically initialized with:

- **4 Institutions**:

  1. Government (Policy type) - capacity 50±20, strength 100
  2. Military (Militant type) - capacity 50±20, strength 100
  3. Media (Civilian type) - capacity 50±20, strength 100
  4. Intelligence Agency (Intelligence type) - capacity 50±20, strength 100

- **4 Dependencies**:
  - Government → Military (0.8 weight)
  - Military → Intelligence (0.6 weight)
  - Government → Media (0.7 weight)
  - Media → Government (0.5 weight, feedback loop)

### Dashboard Indicators

The dashboard displays in real-time:

- **Day**: Current simulation day
- **Cash**: Player's currency (starting $1000)
- **Bandwidth**: Action points (starting 50/100)
- **Exposure**: Visibility of Deep State (0-100%)
- **Tension Bar**: Progress toward crisis (0-100%)

### Console Output

Debug buttons print information to the Godot console:

```
Day advanced to: 5
Added 20 stress to Government (stress: 45.3)
Added 10 tension (total: 35.0)
Added $500 (total: 1500)
Added 25 bandwidth (total: 75)
Added 15 influence to Military (influence: 15.0)
Test event triggered on Media
DEBUG: Triggering crisis at Government
```

### Implementation Notes

- All debug buttons are in the DebugPanel node at bottom of simulation
- Institution card updates happen automatically via signal connections
- Dashboard updates must be called manually (via \_update_dashboard())
- Test region randomizes some initial stats for variety
- Debug buttons do not increase game difficulty or affect scoring

### Future Enhancements

- [ ] Add button to trigger specific event trees
- [ ] Add button to test dependency rewiring
- [ ] Add button to modify specific institution properties
- [ ] Add button to view full game state as JSON
- [ ] Add toggle to enable/disable debug panel
- [ ] Add button to save/load test states
- [ ] Add button to simulate full day sequence at speed
