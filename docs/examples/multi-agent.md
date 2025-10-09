# Multi-Agent Systems

Build collaborative multi-agent systems using KBS blackboard memory for coordination, message passing, and distributed reasoning.

## System Overview

This example demonstrates a smart home automation system with:

- **Multiple Specialized Agents** - Temperature, security, energy, scheduling
- **Blackboard Coordination** - Shared persistent workspace
- **Message Passing** - Inter-agent communication via priority queues
- **Conflict Resolution** - Arbitration when agents disagree
- **Emergent Behavior** - Complex system behavior from simple agent rules

## Architecture

```
┌─────────────────── Blackboard Memory ──────────────────┐
│                                                         │
│  Facts: sensor_reading, alert, command, agent_status   │
│  Messages: priority queues for agent communication     │
│  Audit: complete history of all agent actions          │
│                                                         │
└──────────────────────┬──────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┬──────────────┐
        │              │              │              │
  ┌─────▼────┐   ┌────▼─────┐  ┌────▼─────┐  ┌─────▼────┐
  │ Temp     │   │ Security │  │ Energy   │  │ Schedule │
  │ Agent    │   │ Agent    │  │ Agent    │  │ Agent    │
  └──────────┘   └──────────┘  └──────────┘  └──────────┘
```

## Complete Implementation

### Multi-Agent Smart Home

```ruby
require 'kbs'

# Base agent class
class Agent
  attr_reader :name, :engine

  def initialize(name, engine)
    @name = name
    @engine = engine
    @running = false
  end

  def start
    @running = true
    @engine.add_fact(:agent_status, {
      agent: @name,
      status: "started",
      timestamp: Time.now
    })
  end

  def stop
    @running = false
    @engine.add_fact(:agent_status, {
      agent: @name,
      status: "stopped",
      timestamp: Time.now
    })
  end

  def running?
    @running
  end

  def send_message(topic, content, priority: 50)
    @engine.send_message(topic, {
      from: @name,
      content: content,
      timestamp: Time.now
    }, priority: priority)
  end

  def receive_messages(topic)
    messages = []
    while (msg = @engine.pop_message(topic))
      messages << msg
    end
    messages
  end

  # Override in subclasses
  def process
    raise NotImplementedError, "Subclass must implement process"
  end

  def run_cycle
    return unless running?
    process
  end
end

# Temperature control agent
class TemperatureAgent < Agent
  def initialize(engine, target_temp: 22.0)
    super("TemperatureAgent", engine)
    @target_temp = target_temp
    setup_rules
  end

  def setup_rules
    # Rule 1: Detect high temperature
    high_temp_rule = KBS::Rule.new("detect_high_temperature", priority: 100) do |r|
      r.conditions = [
        KBS::Condition.new(:sensor_reading, {
          type: "temperature",
          location: :?location,
          value: :?temp
        }, predicate: lambda { |f| f[:value] > @target_temp + 2 }),

        KBS::Condition.new(:temperature_alert, {
          location: :?location
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:temperature_alert, {
          location: bindings[:?location],
          temperature: bindings[:?temp],
          severity: "high",
          timestamp: Time.now
        })

        send_message(:hvac_control, {
          action: "cool",
          location: bindings[:?location],
          target: @target_temp
        }, priority: 80)
      end
    end

    # Rule 2: Detect low temperature
    low_temp_rule = KBS::Rule.new("detect_low_temperature", priority: 100) do |r|
      r.conditions = [
        KBS::Condition.new(:sensor_reading, {
          type: "temperature",
          location: :?location,
          value: :?temp
        }, predicate: lambda { |f| f[:value] < @target_temp - 2 }),

        KBS::Condition.new(:temperature_alert, {
          location: :?location
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:temperature_alert, {
          location: bindings[:?location],
          temperature: bindings[:?temp],
          severity: "low",
          timestamp: Time.now
        })

        send_message(:hvac_control, {
          action: "heat",
          location: bindings[:?location],
          target: @target_temp
        }, priority: 80)
      end
    end

    # Rule 3: Clear alert when temperature normalized
    clear_alert_rule = KBS::Rule.new("clear_temperature_alert", priority: 90) do |r|
      r.conditions = [
        KBS::Condition.new(:sensor_reading, {
          type: "temperature",
          location: :?location,
          value: :?temp
        }, predicate: lambda { |f|
          (f[:value] - @target_temp).abs <= 1
        }),

        KBS::Condition.new(:temperature_alert, {
          location: :?location
        })
      ]

      r.action = lambda do |facts, bindings|
        alert = facts.find { |f|
          f.type == :temperature_alert && f[:location] == bindings[:?location]
        }
        @engine.remove_fact(alert) if alert

        send_message(:hvac_control, {
          action: "off",
          location: bindings[:?location]
        }, priority: 50)
      end
    end

    @engine.add_rule(high_temp_rule)
    @engine.add_rule(low_temp_rule)
    @engine.add_rule(clear_alert_rule)
  end

  def process
    @engine.run
  end
end

# Security monitoring agent
class SecurityAgent < Agent
  def initialize(engine)
    super("SecurityAgent", engine)
    setup_rules
  end

  def setup_rules
    # Rule 1: Detect intrusion
    intrusion_rule = KBS::Rule.new("detect_intrusion", priority: 100) do |r|
      r.conditions = [
        KBS::Condition.new(:sensor_reading, {
          type: "motion",
          location: :?location,
          detected: true
        }),

        KBS::Condition.new(:occupancy, {
          status: "away"
        }),

        KBS::Condition.new(:security_alert, {
          type: "intrusion",
          location: :?location
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:security_alert, {
          type: "intrusion",
          location: bindings[:?location],
          severity: "critical",
          timestamp: Time.now
        })

        send_message(:security_system, {
          action: "alarm",
          location: bindings[:?location]
        }, priority: 100)

        send_message(:notifications, {
          type: "security",
          message: "Intrusion detected at #{bindings[:?location]}"
        }, priority: 100)
      end
    end

    # Rule 2: Door left open
    door_open_rule = KBS::Rule.new("detect_door_open", priority: 90) do |r|
      r.conditions = [
        KBS::Condition.new(:sensor_reading, {
          type: "door",
          location: :?location,
          state: "open",
          timestamp: :?time
        }, predicate: lambda { |f|
          (Time.now - f[:timestamp]) > 300  # Open for 5 minutes
        }),

        KBS::Condition.new(:security_alert, {
          type: "door_open",
          location: :?location
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:security_alert, {
          type: "door_open",
          location: bindings[:?location],
          severity: "medium",
          timestamp: Time.now
        })

        send_message(:notifications, {
          type: "security",
          message: "Door at #{bindings[:?location]} left open"
        }, priority: 70)
      end
    end

    @engine.add_rule(intrusion_rule)
    @engine.add_rule(door_open_rule)
  end

  def process
    @engine.run
  end
end

# Energy management agent
class EnergyAgent < Agent
  def initialize(engine, max_usage: 5000)
    super("EnergyAgent", engine)
    @max_usage = max_usage  # watts
    setup_rules
  end

  def setup_rules
    # Rule 1: High energy consumption
    high_consumption_rule = KBS::Rule.new("detect_high_consumption", priority: 80) do |r|
      r.conditions = [
        KBS::Condition.new(:sensor_reading, {
          type: "power",
          value: :?usage
        }, predicate: lambda { |f| f[:value] > @max_usage }),

        KBS::Condition.new(:energy_alert, {
          type: "high_consumption"
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:energy_alert, {
          type: "high_consumption",
          usage: bindings[:?usage],
          limit: @max_usage,
          timestamp: Time.now
        })

        # Request non-essential devices to reduce consumption
        send_message(:device_control, {
          action: "reduce_consumption",
          priority_level: "low"
        }, priority: 60)

        send_message(:notifications, {
          type: "energy",
          message: "High energy usage: #{bindings[:?usage]}W (limit: #{@max_usage}W)"
        }, priority: 60)
      end
    end

    # Rule 2: Coordinate with HVAC during high usage
    hvac_coordination_rule = KBS::Rule.new("coordinate_hvac_energy", priority: 75) do |r|
      r.conditions = [
        KBS::Condition.new(:energy_alert, {
          type: "high_consumption"
        }),

        KBS::Condition.new(:temperature_alert, {
          location: :?location
        })
      ]

      r.action = lambda do |facts, bindings|
        # Ask temperature agent to reduce HVAC intensity
        send_message(:hvac_control, {
          action: "eco_mode",
          location: bindings[:?location]
        }, priority: 70)
      end
    end

    @engine.add_rule(high_consumption_rule)
    @engine.add_rule(hvac_coordination_rule)
  end

  def process
    @engine.run
  end
end

# Scheduling agent
class ScheduleAgent < Agent
  def initialize(engine)
    super("ScheduleAgent", engine)
    setup_rules
  end

  def setup_rules
    # Rule 1: Morning routine
    morning_rule = KBS::Rule.new("morning_routine", priority: 70) do |r|
      r.conditions = [
        KBS::Condition.new(:time_event, {
          event: "morning",
          hour: :?hour
        }),

        KBS::Condition.new(:routine_executed, {
          type: "morning"
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:routine_executed, {
          type: "morning",
          timestamp: Time.now
        })

        # Update occupancy
        @engine.add_fact(:occupancy, { status: "home" })

        # Adjust temperature
        send_message(:temperature_control, {
          action: "set_target",
          temperature: 22
        }, priority: 50)

        # Turn on lights
        send_message(:device_control, {
          action: "lights_on",
          locations: ["bedroom", "kitchen"]
        }, priority: 40)
      end
    end

    # Rule 2: Night routine
    night_rule = KBS::Rule.new("night_routine", priority: 70) do |r|
      r.conditions = [
        KBS::Condition.new(:time_event, {
          event: "night",
          hour: :?hour
        }),

        KBS::Condition.new(:routine_executed, {
          type: "night"
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        @engine.add_fact(:routine_executed, {
          type: "night",
          timestamp: Time.now
        })

        # Update occupancy
        @engine.add_fact(:occupancy, { status: "sleeping" })

        # Lower temperature
        send_message(:temperature_control, {
          action: "set_target",
          temperature: 18
        }, priority: 50)

        # Turn off lights except nightlights
        send_message(:device_control, {
          action: "lights_off",
          exclude: ["bathroom_nightlight"]
        }, priority: 40)

        # Enable security
        send_message(:security_system, {
          action: "arm_night_mode"
        }, priority: 60)
      end
    end

    # Rule 3: Away mode
    away_rule = KBS::Rule.new("away_mode", priority: 70) do |r|
      r.conditions = [
        KBS::Condition.new(:time_event, {
          event: "departure"
        }),

        KBS::Condition.new(:occupancy, {
          status: "away"
        }, negated: true)
      ]

      r.action = lambda do |facts, bindings|
        old_occupancy = @engine.facts.find { |f| f.type == :occupancy }
        @engine.remove_fact(old_occupancy) if old_occupancy

        @engine.add_fact(:occupancy, { status: "away" })

        # Turn off all lights
        send_message(:device_control, {
          action: "all_lights_off"
        }, priority: 40)

        # Energy saving mode
        send_message(:temperature_control, {
          action: "eco_mode"
        }, priority: 50)

        # Arm security
        send_message(:security_system, {
          action: "arm_away_mode"
        }, priority: 80)
      end
    end

    @engine.add_rule(morning_rule)
    @engine.add_rule(night_rule)
    @engine.add_rule(away_rule)
  end

  def process
    @engine.run
  end
end

# Arbitration agent - resolves conflicts
class ArbitrationAgent < Agent
  def initialize(engine)
    super("ArbitrationAgent", engine)
    setup_rules
  end

  def setup_rules
    # Rule: Security overrides energy savings
    security_priority_rule = KBS::Rule.new("security_overrides_energy", priority: 95) do |r|
      r.conditions = [
        KBS::Condition.new(:security_alert, {
          severity: "critical"
        }),

        KBS::Condition.new(:energy_alert, {
          type: "high_consumption"
        })
      ]

      r.action = lambda do |facts, bindings|
        # Cancel energy reduction requests
        send_message(:device_control, {
          action: "cancel_energy_reduction",
          reason: "security_priority"
        }, priority: 95)

        # Notify
        send_message(:notifications, {
          type: "system",
          message: "Security takes priority over energy savings"
        }, priority: 90)
      end
    end

    # Rule: Comfort overrides energy during occupied hours
    comfort_priority_rule = KBS::Rule.new("comfort_during_occupied", priority: 85) do |r|
      r.conditions = [
        KBS::Condition.new(:occupancy, {
          status: :?status
        }, predicate: lambda { |f| f[:status] == "home" || f[:status] == "sleeping" }),

        KBS::Condition.new(:temperature_alert, {
          severity: :?severity
        }),

        KBS::Condition.new(:energy_alert, {
          type: "high_consumption"
        })
      ]

      r.action = lambda do |facts, bindings|
        # Allow HVAC to continue despite high energy
        send_message(:hvac_control, {
          action: "maintain_comfort",
          reason: "occupancy_priority"
        }, priority: 85)
      end
    end

    @engine.add_rule(security_priority_rule)
    @engine.add_rule(comfort_priority_rule)
  end

  def process
    @engine.run
  end
end

# Multi-agent system coordinator
class SmartHomeSystem
  attr_reader :engine, :agents

  def initialize(db_path: 'smart_home.db')
    @engine = KBS::Blackboard::Engine.new(db_path: db_path)
    @agents = []
    @running = false

    setup_agents
  end

  def setup_agents
    @agents << TemperatureAgent.new(@engine, target_temp: 22.0)
    @agents << SecurityAgent.new(@engine)
    @agents << EnergyAgent.new(@engine, max_usage: 5000)
    @agents << ScheduleAgent.new(@engine)
    @agents << ArbitrationAgent.new(@engine)
  end

  def start
    @running = true
    @agents.each(&:start)

    puts "Smart Home System started with #{@agents.size} agents"
  end

  def stop
    @running = false
    @agents.each(&:stop)

    @engine.close
    puts "Smart Home System stopped"
  end

  def add_sensor_reading(type, attributes)
    @engine.add_fact(:sensor_reading, {
      type: type,
      timestamp: Time.now,
      **attributes
    })
  end

  def trigger_time_event(event, attributes = {})
    @engine.add_fact(:time_event, {
      event: event,
      timestamp: Time.now,
      **attributes
    })
  end

  def run_cycle
    # Each agent processes in sequence
    @agents.each(&:run_cycle)
  end

  def run_continuous(interval: 1)
    while @running
      run_cycle
      sleep interval
    end
  end

  def status
    {
      running: @running,
      agents: @agents.map { |a| { name: a.name, running: a.running? } },
      facts: @engine.facts.size,
      alerts: @engine.facts.select { |f| f.type.to_s.include?("alert") }.size
    }
  end
end

# Usage Example 1: Temperature Control
puts "=== Example 1: Temperature Control ==="
system = SmartHomeSystem.new(db_path: ':memory:')
system.start

# Add temperature reading
system.add_sensor_reading("temperature", {
  location: "living_room",
  value: 26.0  # Above target (22°C)
})

# Run agent cycle
system.run_cycle

# Check for temperature alerts
alerts = system.engine.facts.select { |f| f.type == :temperature_alert }
puts "\nTemperature Alerts:"
alerts.each do |alert|
  puts "  Location: #{alert[:location]}"
  puts "  Temperature: #{alert[:temperature]}°C"
  puts "  Severity: #{alert[:severity]}"
end

# Check HVAC messages
hvac_messages = []
while (msg = system.engine.pop_message(:hvac_control))
  hvac_messages << msg
end

puts "\nHVAC Control Messages:"
hvac_messages.each do |msg|
  puts "  From: #{msg[:content][:from]}"
  puts "  Action: #{msg[:content][:content][:action]}"
  puts "  Priority: #{msg[:priority]}"
end

# Usage Example 2: Security Event
puts "\n\n=== Example 2: Security Event ==="
system2 = SmartHomeSystem.new(db_path: ':memory:')
system2.start

# Set away mode
system2.engine.add_fact(:occupancy, { status: "away" })

# Motion detected while away
system2.add_sensor_reading("motion", {
  location: "living_room",
  detected: true
})

system2.run_cycle

# Check security alerts
security_alerts = system2.engine.facts.select { |f| f.type == :security_alert }
puts "\nSecurity Alerts:"
security_alerts.each do |alert|
  puts "  Type: #{alert[:type]}"
  puts "  Location: #{alert[:location]}"
  puts "  Severity: #{alert[:severity]}"
end

# Check notifications
notifications = []
while (msg = system2.engine.pop_message(:notifications))
  notifications << msg
end

puts "\nNotifications:"
notifications.each do |msg|
  puts "  Type: #{msg[:content][:content][:type]}"
  puts "  Message: #{msg[:content][:content][:message]}"
  puts "  Priority: #{msg[:priority]}"
end

# Usage Example 3: Energy Management with Arbitration
puts "\n\n=== Example 3: Energy Management ==="
system3 = SmartHomeSystem.new(db_path: ':memory:')
system3.start

# High energy consumption
system3.add_sensor_reading("power", { value: 6000 })  # Above 5000W limit

# Also high temperature (competing concern)
system3.add_sensor_reading("temperature", {
  location: "bedroom",
  value: 26.0
})

# Home occupancy
system3.engine.add_fact(:occupancy, { status: "home" })

system3.run_cycle

# Check arbitration
energy_alerts = system3.engine.facts.select { |f| f.type == :energy_alert }
temp_alerts = system3.engine.facts.select { |f| f.type == :temperature_alert }

puts "\nEnergy Alerts: #{energy_alerts.size}"
puts "Temperature Alerts: #{temp_alerts.size}"

# HVAC should maintain comfort despite high energy (arbitration)
hvac_msgs = []
while (msg = system3.engine.pop_message(:hvac_control))
  hvac_msgs << msg
end

puts "\nHVAC Messages:"
hvac_msgs.each do |msg|
  puts "  Action: #{msg[:content][:content][:action]}"
end

# Usage Example 4: Morning Routine
puts "\n\n=== Example 4: Morning Routine ==="
system4 = SmartHomeSystem.new(db_path: ':memory:')
system4.start

# Trigger morning event
system4.trigger_time_event("morning", { hour: 7 })

system4.run_cycle

# Check messages sent to various subsystems
temp_msgs = []
while (msg = system4.engine.pop_message(:temperature_control))
  temp_msgs << msg
end

device_msgs = []
while (msg = system4.engine.pop_message(:device_control))
  device_msgs << msg
end

puts "\nMorning Routine Executed:"
puts "  Temperature control messages: #{temp_msgs.size}"
puts "  Device control messages: #{device_msgs.size}"

temp_msgs.each do |msg|
  puts "  - Set temperature to #{msg[:content][:content][:temperature]}°C"
end

device_msgs.each do |msg|
  puts "  - #{msg[:content][:content][:action]}"
end

puts "\nSystem Status:"
puts system4.status.inspect
```

## Key Features

### 1. Agent Autonomy

Each agent operates independently:

```ruby
class Agent
  def run_cycle
    return unless running?
    process  # Agent-specific logic
  end
end
```

### 2. Blackboard Coordination

Shared workspace for collaboration:

```ruby
# Agent 1 writes fact
@engine.add_fact(:temperature_alert, { location: "bedroom" })

# Agent 2 reads fact and responds
temperature_alert = @engine.facts.find { |f|
  f.type == :temperature_alert && f[:location] == "bedroom"
}
```

### 3. Message Passing

Priority-based communication:

```ruby
# Temperature agent sends message
send_message(:hvac_control, {
  action: "cool",
  location: "bedroom"
}, priority: 80)

# HVAC controller receives message
msg = @engine.pop_message(:hvac_control)
# Process highest priority message first
```

### 4. Conflict Resolution

Arbitration agent resolves competing goals:

```ruby
# Security overrides energy savings
KBS::Rule.new("security_overrides_energy") do |r|
  r.conditions = [
    KBS::Condition.new(:security_alert, { severity: "critical" }),
    KBS::Condition.new(:energy_alert, { type: "high_consumption" })
  ]

  r.action = lambda do |facts, bindings|
    # Cancel energy reduction
    send_message(:device_control, {
      action: "cancel_energy_reduction",
      reason: "security_priority"
    }, priority: 95)
  end
end
```

### 5. Emergent Behavior

Complex system behavior from simple agent rules:

```ruby
# Temperature agent: "Keep temperature at 22°C"
# Energy agent: "Don't exceed 5000W"
# Arbitration agent: "Comfort during occupied hours"
# Result: System automatically balances comfort and efficiency
```

## Multi-Agent Patterns

### Agent Roles

**Reactive Agents**: Respond to immediate stimuli

```ruby
class ReactiveAgent < Agent
  def process
    # React to current sensor readings
    sensor_facts = @engine.facts.select { |f| f.type == :sensor_reading }
    sensor_facts.each { |fact| react_to(fact) }
  end
end
```

**Proactive Agents**: Plan and execute goals

```ruby
class ProactiveAgent < Agent
  def process
    # Check goals
    goals = @engine.facts.select { |f| f.type == :goal }
    goals.each { |goal| plan_for(goal) }
  end
end
```

**Social Agents**: Collaborate with other agents

```ruby
class SocialAgent < Agent
  def process
    # Coordinate with other agents
    messages = receive_messages(:coordination)
    messages.each { |msg| coordinate_with(msg) }
  end
end
```

### Communication Protocols

**Request-Reply**:

```ruby
# Agent A sends request
send_message(:task_queue, {
  type: "request",
  request_id: SecureRandom.uuid,
  action: "analyze_data"
}, priority: 50)

# Agent B processes and replies
request = @engine.pop_message(:task_queue)
result = process_request(request)

send_message(:responses, {
  type: "reply",
  request_id: request[:content][:request_id],
  result: result
}, priority: 60)
```

**Broadcast**:

```ruby
# Agent sends to all
@engine.add_fact(:broadcast, {
  from: @name,
  message: "System shutdown in 5 minutes"
})

# All agents read
broadcasts = @engine.facts.select { |f|
  f.type == :broadcast && f[:from] != @name
}
```

**Negotiation**:

```ruby
# Agent proposes
@engine.add_fact(:proposal, {
  from: @name,
  resource: "hvac_bedroom",
  duration: 30,
  priority: 5
})

# Other agents bid or decline
existing_proposals = @engine.facts.select { |f| f.type == :proposal }
if can_accept?(existing_proposals)
  @engine.add_fact(:acceptance, { proposal_id: proposal.id })
else
  @engine.add_fact(:counter_proposal, { ... })
end
```

### Coordination Strategies

**Centralized Coordination**:

```ruby
class CoordinatorAgent < Agent
  def process
    # Collect all agent requests
    requests = []
    @agents.each do |agent|
      while (msg = @engine.pop_message(:"#{agent.name}_requests"))
        requests << msg
      end
    end

    # Optimize schedule
    schedule = optimize_schedule(requests)

    # Dispatch commands
    schedule.each do |task|
      send_message(:"#{task[:agent]}_commands", task, priority: 70)
    end
  end
end
```

**Distributed Coordination**:

```ruby
class DistributedAgent < Agent
  def process
    # Each agent coordinates locally
    neighbors = find_neighbors
    neighbors.each do |neighbor|
      send_message(:"#{neighbor}_coordination", {
        from: @name,
        state: current_state
      }, priority: 50)
    end

    # Adjust based on neighbor states
    neighbor_states = receive_messages(:"#{@name}_coordination")
    adjust_behavior(neighbor_states)
  end
end
```

**Market-Based Coordination**:

```ruby
class MarketAgent < Agent
  def process
    # Bid on tasks based on cost
    tasks = @engine.facts.select { |f| f.type == :available_task }

    tasks.each do |task|
      cost = calculate_cost(task)
      @engine.add_fact(:bid, {
        agent: @name,
        task_id: task.id,
        cost: cost
      })
    end

    # Winner takes task
    my_bids = @engine.facts.select { |f|
      f.type == :bid && f[:agent] == @name
    }

    my_bids.each do |bid|
      if winning_bid?(bid)
        execute_task(bid[:task_id])
      end
    end
  end
end
```

## Advanced Features

### Agent Discovery

```ruby
def discover_agents
  agent_statuses = @engine.facts.select { |f| f.type == :agent_status }
  active_agents = agent_statuses.select { |a| a[:status] == "started" }

  active_agents.map { |a| a[:agent] }
end
```

### Dynamic Agent Creation

```ruby
def spawn_agent(agent_class, *args)
  new_agent = agent_class.new(@engine, *args)
  @agents << new_agent
  new_agent.start
  new_agent
end

# Example: Spawn specialist agent
if complex_problem_detected?
  specialist = spawn_agent(SpecialistAgent, problem_type)
end
```

### Agent Lifecycle Management

```ruby
class AgentManager
  def initialize(engine)
    @engine = engine
    @agents = {}
  end

  def register(agent)
    @agents[agent.name] = agent

    @engine.add_fact(:agent_registered, {
      name: agent.name,
      type: agent.class.name,
      timestamp: Time.now
    })
  end

  def deregister(agent_name)
    agent = @agents.delete(agent_name)
    agent&.stop

    @engine.add_fact(:agent_deregistered, {
      name: agent_name,
      timestamp: Time.now
    })
  end

  def monitor_agents
    @agents.each do |name, agent|
      unless agent.running?
        # Restart failed agent
        agent.start
        @engine.add_fact(:agent_restarted, {
          name: name,
          timestamp: Time.now
        })
      end
    end
  end
end
```

### Fault Tolerance

```ruby
class FaultTolerantAgent < Agent
  def run_cycle
    return unless running?

    begin
      process
    rescue => e
      handle_error(e)
    end
  end

  def handle_error(error)
    @engine.add_fact(:agent_error, {
      agent: @name,
      error: error.message,
      timestamp: Time.now
    })

    send_message(:system_alerts, {
      type: "agent_failure",
      agent: @name,
      error: error.message
    }, priority: 100)

    # Attempt recovery
    attempt_recovery
  end

  def attempt_recovery
    # Restart agent's subsystems
    # Or notify manager for replacement
  end
end
```

## Testing

```ruby
require 'minitest/autorun'

class TestMultiAgentSystem < Minitest::Test
  def setup
    @system = SmartHomeSystem.new(db_path: ':memory:')
    @system.start
  end

  def teardown
    @system.stop
  end

  def test_temperature_agent_creates_alert
    @system.add_sensor_reading("temperature", {
      location: "bedroom",
      value: 26.0
    })

    @system.run_cycle

    alerts = @system.engine.facts.select { |f| f.type == :temperature_alert }

    assert_equal 1, alerts.size
    assert_equal "bedroom", alerts.first[:location]
    assert_equal "high", alerts.first[:severity]
  end

  def test_security_agent_detects_intrusion
    @system.engine.add_fact(:occupancy, { status: "away" })

    @system.add_sensor_reading("motion", {
      location: "living_room",
      detected: true
    })

    @system.run_cycle

    alerts = @system.engine.facts.select { |f|
      f.type == :security_alert && f[:type] == "intrusion"
    }

    assert_equal 1, alerts.size
    assert_equal "critical", alerts.first[:severity]
  end

  def test_energy_agent_triggers_reduction
    @system.add_sensor_reading("power", { value: 6000 })

    @system.run_cycle

    energy_alerts = @system.engine.facts.select { |f|
      f.type == :energy_alert
    }

    assert_equal 1, energy_alerts.size

    # Check for reduction message
    msg = @system.engine.pop_message(:device_control)
    assert msg
    assert_equal "reduce_consumption", msg[:content][:content][:action]
  end

  def test_arbitration_security_over_energy
    # Create conflict: security alert + energy alert
    @system.engine.add_fact(:security_alert, {
      type: "intrusion",
      severity: "critical"
    })

    @system.add_sensor_reading("power", { value: 6000 })

    @system.run_cycle

    # Arbitration should send cancellation
    msg = @system.engine.pop_message(:device_control)
    while msg
      if msg[:content][:content][:action] == "cancel_energy_reduction"
        assert_equal "security_priority", msg[:content][:content][:reason]
        return
      end
      msg = @system.engine.pop_message(:device_control)
    end

    flunk "Expected cancellation message not found"
  end

  def test_schedule_agent_morning_routine
    @system.trigger_time_event("morning", { hour: 7 })

    @system.run_cycle

    # Check occupancy updated
    occupancy = @system.engine.facts.find { |f| f.type == :occupancy }
    assert_equal "home", occupancy[:status]

    # Check routine executed
    routine = @system.engine.facts.find { |f|
      f.type == :routine_executed && f[:type] == "morning"
    }
    assert routine
  end

  def test_agent_coordination_via_messages
    temp_agent = @system.agents.find { |a| a.is_a?(TemperatureAgent) }

    @system.add_sensor_reading("temperature", {
      location: "bedroom",
      value: 26.0
    })

    @system.run_cycle

    # Temperature agent should send HVAC message
    msg = @system.engine.pop_message(:hvac_control)

    assert msg
    assert_equal "TemperatureAgent", msg[:content][:from]
    assert_equal "cool", msg[:content][:content][:action]
  end

  def test_system_status
    status = @system.status

    assert status[:running]
    assert_equal 5, status[:agents].size
    assert status[:agents].all? { |a| a[:running] }
  end
end
```

## Performance Considerations

### Use Redis for High-Throughput

```ruby
require 'kbs/blackboard/persistence/redis_store'

store = KBS::Blackboard::Persistence::RedisStore.new(
  url: 'redis://localhost:6379/0'
)

system = SmartHomeSystem.new(store: store)
# 100x faster message passing
```

### Agent Thread Pools

```ruby
require 'concurrent'

class ThreadedSmartHomeSystem < SmartHomeSystem
  def run_continuous(interval: 1)
    pool = Concurrent::FixedThreadPool.new(5)

    while @running
      @agents.each do |agent|
        pool.post { agent.run_cycle }
      end

      sleep interval
    end

    pool.shutdown
    pool.wait_for_termination
  end
end
```

## Next Steps

- **[Blackboard Memory](../guides/blackboard-memory.md)** - Shared workspace details
- **[Performance Guide](../advanced/performance.md)** - Optimize multi-agent systems
- **[Testing Guide](../advanced/testing.md)** - Test agent interactions
- **[API Reference](../api/blackboard.md)** - Blackboard API

---

*Multi-agent systems enable emergent intelligence through collaboration. Each agent contributes specialized expertise, and the system as a whole solves problems no single agent could solve alone.*
