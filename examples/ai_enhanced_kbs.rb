#!/usr/bin/env ruby

require 'ruby_llm'
require 'ruby_llm/mcp'
require_relative '../lib/kbs'
require 'json'
require 'date'

# Configure RubyLLM for Ollama
RubyLLM.configure do |config|
  config.ollama_api_base = ENV['OLLAMA_API_BASE'] || 'http://localhost:11434'
end

module AIEnhancedKBS
  class AIKnowledgeSystem
    def initialize
      @engine = KBS::ReteEngine.new
      @ai_client = setup_ai_client
      @mcp_agent = setup_mcp_agent
      @sentiment_cache = {}
      @explanation_cache = {}
      setup_ai_enhanced_rules
    end

    def setup_ai_client
      model = ENV['OLLAMA_MODEL'] || 'gpt-oss:latest'
      puts "🤖 Initializing RubyLLM::Chat with Ollama model: #{model}"
      RubyLLM::Chat.new(provider: :ollama, model: model)
    end

    def setup_mcp_agent
      if defined?(RubyLLM::MCP::Agent)
        RubyLLM::MCP::Agent.new(
          name: "market_analyst",
          description: "AI agent for market analysis and trading insights"
        )
      else
        nil
      end
    end

    def setup_ai_enhanced_rules
      # Rule 1: AI-Powered Sentiment Analysis
      sentiment_rule = KBS::Rule.new(
        "ai_sentiment_analysis",
        conditions: [
          KBS::Condition.new(:news_data, {
            symbol: ->(s) { s && s.length > 0 },
            headline: ->(h) { h && h.length > 10 },
            content: ->(c) { c && c.length > 50 }
          })
        ],
        action: lambda do |facts, bindings|
          news = facts.find { |f| f.type == :news_data }
          symbol = news[:symbol]

          # AI-powered sentiment analysis
          sentiment = analyze_sentiment_with_ai(news[:headline], news[:content])

          puts "🤖 AI SENTIMENT ANALYSIS: #{symbol}"
          puts "   Headline: #{news[:headline][0..80]}..."
          puts "   AI Sentiment: #{sentiment[:sentiment]} (#{sentiment[:confidence]}%)"
          puts "   Key Themes: #{sentiment[:themes].join(', ')}"
          puts "   Market Impact: #{sentiment[:market_impact]}"

          # Add sentiment fact to working memory
          @engine.add_fact(:ai_sentiment, {
            symbol: symbol,
            sentiment_score: sentiment[:score],
            confidence: sentiment[:confidence],
            themes: sentiment[:themes],
            market_impact: sentiment[:market_impact],
            timestamp: Time.now
          })
        end,
        priority: 20
      )

      # Rule 2: AI-Generated Trading Strategy
      ai_strategy_rule = KBS::Rule.new(
        "ai_strategy_generation",
        conditions: [
          KBS::Condition.new(:market_conditions, {
            volatility: ->(v) { v && v > 25 },
            trend: ->(t) { t && t.length > 0 }
          }),
          KBS::Condition.new(:portfolio_state, {
            cash_ratio: ->(c) { c && c > 0.2 }
          })
        ],
        action: lambda do |facts, bindings|
          market = facts.find { |f| f.type == :market_conditions }
          portfolio = facts.find { |f| f.type == :portfolio_state }

          # Generate AI strategy
          strategy = generate_ai_trading_strategy(market, portfolio)

          puts "🧠 AI TRADING STRATEGY"
          puts "   Market Context: #{market[:trend]} trend, #{market[:volatility]}% volatility"
          puts "   Strategy: #{strategy[:name]}"
          puts "   Rationale: #{strategy[:rationale]}"
          puts "   Actions: #{strategy[:actions].join(', ')}"
          puts "   Risk Level: #{strategy[:risk_level]}"

          # Execute AI-suggested actions (would be implemented in production)
          # execute_ai_strategy(strategy)
        end,
        priority: 15
      )

      # Rule 3: Dynamic Rule Generation
      dynamic_rule_creation = KBS::Rule.new(
        "dynamic_rule_creation",
        conditions: [
          KBS::Condition.new(:pattern_anomaly, {
            pattern_type: ->(p) { p && p.length > 0 },
            confidence: ->(c) { c && c > 0.8 },
            occurrences: ->(o) { o && o > 5 }
          })
        ],
        action: lambda do |facts, bindings|
          anomaly = facts.find { |f| f.type == :pattern_anomaly }

          # AI generates new trading rule
          new_rule_spec = generate_rule_with_ai(anomaly)

          puts "🎯 AI RULE GENERATION"
          puts "   Pattern: #{anomaly[:pattern_type]}"
          puts "   New Rule: #{new_rule_spec[:name]}"
          puts "   Logic: #{new_rule_spec[:description]}"

          # Dynamically add new rule to engine
          if new_rule_spec[:valid]
            dynamic_rule = create_rule_from_spec(new_rule_spec)
            @engine.add_rule(dynamic_rule)
            puts "   ✅ Rule added to knowledge base"
          end
        end,
        priority: 12
      )

      # Rule 4: AI Risk Assessment
      ai_risk_assessment = KBS::Rule.new(
        "ai_risk_assessment",
        conditions: [
          KBS::Condition.new(:position, {
            unrealized_pnl: ->(pnl) { pnl && pnl.abs > 1000 }
          }),
          KBS::Condition.new(:market_data, {
            symbol: ->(s) { s && s.length > 0 }
          })
        ],
        action: lambda do |facts, bindings|
          position = facts.find { |f| f.type == :position }
          market_data = facts.find { |f| f.type == :market_data }

          # AI-powered risk analysis
          risk_analysis = analyze_position_risk_with_ai(position, market_data)

          puts "⚠️  AI RISK ASSESSMENT: #{position[:symbol]}"
          puts "   Current P&L: $#{position[:unrealized_pnl]}"
          puts "   Risk Level: #{risk_analysis[:risk_level]}"
          puts "   Key Risks: #{risk_analysis[:risks].join(', ')}"
          puts "   Recommendation: #{risk_analysis[:recommendation]}"
          puts "   Confidence: #{risk_analysis[:confidence]}%"

          # Act on high-risk situations
          if risk_analysis[:risk_level] == "HIGH" && risk_analysis[:confidence] > 80
            puts "   🚨 HIGH RISK DETECTED - Consider position adjustment"
          end
        end,
        priority: 18
      )

      # Rule 5: Natural Language Explanation Generator
      explanation_rule = KBS::Rule.new(
        "ai_explanation_generator",
        conditions: [
          KBS::Condition.new(:trade_recommendation, {
            action: ->(a) { ["BUY", "SELL", "HOLD"].include?(a) },
            symbol: ->(s) { s && s.length > 0 }
          })
        ],
        action: lambda do |facts, bindings|
          recommendation = facts.find { |f| f.type == :trade_recommendation }

          # Generate natural language explanation
          explanation = generate_trade_explanation(recommendation, facts)

          puts "💬 AI EXPLANATION: #{recommendation[:symbol]} #{recommendation[:action]}"
          puts "   Reasoning: #{explanation[:reasoning]}"
          puts "   Context: #{explanation[:context]}"
          puts "   Confidence: #{explanation[:confidence]}%"
          puts "   Alternative View: #{explanation[:alternative]}"
        end,
        priority: 5
      )

      # Rule 6: AI Pattern Recognition
      pattern_recognition_rule = KBS::Rule.new(
        "ai_pattern_recognition",
        conditions: [
          KBS::Condition.new(:price_history, {
            symbol: ->(s) { s && s.length > 0 },
            data_points: ->(d) { d && d.length >= 30 }
          })
        ],
        action: lambda do |facts, bindings|
          price_data = facts.find { |f| f.type == :price_history }

          # AI identifies patterns
          patterns = identify_patterns_with_ai(price_data[:data_points])

          if patterns.any?
            puts "📊 AI PATTERN RECOGNITION: #{price_data[:symbol]}"
            patterns.each do |pattern|
              puts "   Pattern: #{pattern[:name]} (#{pattern[:confidence]}%)"
              puts "   Prediction: #{pattern[:prediction]}"
              puts "   Time Horizon: #{pattern[:time_horizon]}"
            end
          end
        end,
        priority: 10
      )

      @engine.add_rule(sentiment_rule)
      @engine.add_rule(ai_strategy_rule)
      @engine.add_rule(dynamic_rule_creation)
      @engine.add_rule(ai_risk_assessment)
      @engine.add_rule(explanation_rule)
      @engine.add_rule(pattern_recognition_rule)
    end

    def analyze_sentiment_with_ai(headline, content)
      cache_key = "#{headline[0..50]}_#{content[0..100]}".hash
      return @sentiment_cache[cache_key] if @sentiment_cache[cache_key]

      prompt = build_sentiment_prompt(headline, content)
      puts "\n🔗 Calling RubyLLM for sentiment analysis..."

      message = @ai_client.ask(prompt)
      response_text = message.content.to_s
      puts "✅ Got response from Ollama (#{response_text.length} chars)"
      puts "📝 Response: #{response_text[0..200]}..." if response_text.length > 200

      result = parse_sentiment_response(response_text)

      @sentiment_cache[cache_key] = result
      result
    end

    def generate_ai_trading_strategy(market_conditions, portfolio_state)
      prompt = build_strategy_prompt(market_conditions, portfolio_state)
      puts "\n🔗 Calling RubyLLM for trading strategy..."

      message = @ai_client.ask(prompt)
      response_text = message.content.to_s
      puts "✅ Got response from Ollama (#{response_text.length} chars)"
      puts "📝 Response: #{response_text[0..200]}..." if response_text.length > 200

      parse_strategy_response(response_text)
    end

    def generate_rule_with_ai(anomaly_data)
      prompt = build_rule_generation_prompt(anomaly_data)
      puts "\n🔗 Calling RubyLLM for rule generation..."

      message = @ai_client.ask(prompt)
      response_text = message.content.to_s
      puts "✅ Got response from Ollama (#{response_text.length} chars)"
      puts "📝 Response: #{response_text[0..200]}..." if response_text.length > 200

      parse_rule_specification(response_text)
    end

    def analyze_position_risk_with_ai(position, market_data)
      prompt = build_risk_analysis_prompt(position, market_data)
      puts "\n🔗 Calling RubyLLM for risk analysis..."

      message = @ai_client.ask(prompt)
      response_text = message.content.to_s
      puts "✅ Got response from Ollama (#{response_text.length} chars)"
      puts "📝 Response: #{response_text[0..200]}..." if response_text.length > 200

      parse_risk_analysis(response_text)
    end

    def generate_trade_explanation(recommendation, context_facts)
      cache_key = "#{recommendation[:symbol]}_#{recommendation[:action]}_#{context_facts.length}".hash
      return @explanation_cache[cache_key] if @explanation_cache[cache_key]

      prompt = build_explanation_prompt(recommendation, context_facts)
      puts "\n🔗 Calling RubyLLM for trade explanation..."

      message = @ai_client.ask(prompt)
      response_text = message.content.to_s
      puts "✅ Got response from Ollama (#{response_text.length} chars)"
      puts "📝 Response: #{response_text[0..200]}..." if response_text.length > 200

      result = parse_explanation_response(response_text)

      @explanation_cache[cache_key] = result
      result
    end

    def identify_patterns_with_ai(price_data)
      prompt = build_pattern_recognition_prompt(price_data)
      puts "\n🔗 Calling RubyLLM for pattern recognition..."

      message = @ai_client.ask(prompt)
      response_text = message.content.to_s
      puts "✅ Got response from Ollama (#{response_text.length} chars)"
      puts "📝 Response: #{response_text[0..200]}..." if response_text.length > 200

      parse_pattern_response(response_text)
    end

    # Prompt builders
    def build_sentiment_prompt(headline, content)
      <<~PROMPT
        Analyze the sentiment of this financial news for trading implications:

        Headline: #{headline}
        Content: #{content[0..500]}...

        Provide a JSON response with:
        {
          "sentiment": "positive|negative|neutral",
          "score": -1.0 to 1.0,
          "confidence": 0-100,
          "themes": ["theme1", "theme2"],
          "market_impact": "bullish|bearish|neutral"
        }
      PROMPT
    end

    def build_strategy_prompt(market_conditions, portfolio_state)
      <<~PROMPT
        Generate a trading strategy for these conditions:

        Market: #{market_conditions[:trend]} trend, #{market_conditions[:volatility]}% volatility
        Portfolio: #{(portfolio_state[:cash_ratio] * 100).round(1)}% cash

        Provide a JSON strategy with:
        {
          "name": "strategy_name",
          "rationale": "why this strategy fits",
          "actions": ["action1", "action2"],
          "risk_level": "LOW|MEDIUM|HIGH"
        }
      PROMPT
    end

    def build_risk_analysis_prompt(position, market_data)
      <<~PROMPT
        Analyze the risk of this trading position:

        Position: #{position[:symbol]}, P&L: $#{position[:unrealized_pnl]}
        Market Data: #{market_data.to_json}

        Provide risk assessment as JSON:
        {
          "risk_level": "LOW|MEDIUM|HIGH",
          "risks": ["risk1", "risk2"],
          "recommendation": "hold|reduce|exit",
          "confidence": 0-100
        }
      PROMPT
    end

    def build_explanation_prompt(recommendation, context_facts)
      <<~PROMPT
        Explain this trading recommendation in simple terms:

        Recommendation: #{recommendation[:action]} #{recommendation[:symbol]}
        Context: #{context_facts.length} supporting facts

        Provide explanation as JSON:
        {
          "explanation": "clear explanation",
          "reasoning": "why this makes sense",
          "risks": ["risk1", "risk2"]
        }
      PROMPT
    end

    def build_pattern_recognition_prompt(price_data)
      <<~PROMPT
        Identify trading patterns in this price data:

        Data: #{price_data.to_json}

        Return JSON array of patterns:
        [
          {
            "pattern": "pattern_name",
            "confidence": 0-100,
            "description": "what this means"
          }
        ]
      PROMPT
    end

    # Response parsers
    def extract_json(response)
      # Strip markdown code fences if present
      json_text = response.strip
      json_text = json_text.gsub(/^```json\s*/, '').gsub(/```\s*$/, '').strip
      json_text
    end

    def parse_sentiment_response(response)
      JSON.parse(extract_json(response), symbolize_names: true)
    end

    def parse_strategy_response(response)
      JSON.parse(extract_json(response), symbolize_names: true)
    end

    def parse_explanation_response(response)
      JSON.parse(extract_json(response), symbolize_names: true)
    end

    def parse_pattern_response(response)
      JSON.parse(extract_json(response), symbolize_names: true)
    end

    def parse_risk_analysis(response)
      JSON.parse(extract_json(response), symbolize_names: true)
    end

    def demonstrate_ai_enhancements
      puts "🤖 AI-ENHANCED KNOWLEDGE-BASED SYSTEM"
      puts "=" * 70
      puts "Integrating #{@ai_client.class.name} and #{@mcp_agent.class.name}"
      puts "=" * 70

      # Scenario 1: AI Sentiment Analysis
      puts "\n📰 SCENARIO 1: AI-Powered News Sentiment"
      puts "-" * 50
      @engine.working_memory.facts.clear

      @engine.add_fact(:news_data, {
        symbol: "AAPL",
        headline: "Apple Reports Record Q4 Earnings, Beats Expectations by 15%",
        content: "Apple Inc. announced exceptional fourth quarter results today, with revenue growing 12% year-over-year to $94.9 billion. iPhone sales exceeded analysts' expectations, driven by strong demand for the iPhone 15 Pro models. The company also announced a new $90 billion share buyback program and increased its dividend by 4%. CEO Tim Cook expressed optimism about the AI integration roadmap and services growth trajectory.",
        published_at: Time.now
      })
      @engine.run

      # Scenario 2: AI Strategy Generation
      puts "\n🧠 SCENARIO 2: AI Trading Strategy Generation"
      puts "-" * 50
      @engine.working_memory.facts.clear

      @engine.add_fact(:market_conditions, {
        volatility: 28.5,
        trend: "sideways",
        sector_rotation: "technology_to_healthcare"
      })

      @engine.add_fact(:portfolio_state, {
        cash_ratio: 0.25,
        largest_position: "AAPL",
        sector_concentration: 0.45
      })
      @engine.run

      # Scenario 3: AI Risk Assessment
      puts "\n⚠️  SCENARIO 3: AI Risk Assessment"
      puts "-" * 50
      @engine.working_memory.facts.clear

      @engine.add_fact(:position, {
        symbol: "TSLA",
        shares: 100,
        entry_price: 250.00,
        current_price: 235.00,
        unrealized_pnl: -1500
      })

      @engine.add_fact(:market_data, {
        symbol: "TSLA",
        volatility: 45.2,
        beta: 2.1,
        sector: "Consumer Discretionary"
      })
      @engine.run

      # Scenario 4: Trade Explanation
      puts "\n💬 SCENARIO 4: AI Trade Explanation"
      puts "-" * 50
      @engine.working_memory.facts.clear

      @engine.add_fact(:trade_recommendation, {
        symbol: "GOOGL",
        action: "BUY",
        quantity: 50,
        confidence: 85
      })

      @engine.add_fact(:technical_analysis, {
        symbol: "GOOGL",
        rsi: 35,
        moving_average_signal: "golden_cross",
        volume_trend: "increasing"
      })
      @engine.run

      puts "\n" + "=" * 70
      puts "AI ENHANCEMENT DEMONSTRATION COMPLETE"
      puts "🎯 The system now combines rule-based logic with AI insights"
      puts "🧠 Dynamic pattern recognition and strategy generation"
      puts "💬 Natural language explanations for all decisions"
      puts "⚡ Real-time sentiment analysis and risk assessment"
    end
  end
end

if __FILE__ == $0
  system = AIEnhancedKBS::AIKnowledgeSystem.new
  system.demonstrate_ai_enhancements
end
