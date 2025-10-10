#!/usr/bin/env ruby

require 'ruby_llm'
require 'ruby_llm/mcp'
require_relative '../lib/kbs/dsl'
require 'json'
require 'date'

# Configure RubyLLM for Ollama
RubyLLM.configure do |config|
  config.ollama_api_base = ENV['OLLAMA_API_BASE'] || 'http://localhost:11434'
end

module AIEnhancedKBS
  class AIKnowledgeSystem
    include KBS::DSL::ConditionHelpers

    attr_reader :kb

    def initialize
      @kb = nil
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
      ai_sys = self  # Capture self for use in perform blocks
      @kb = KBS.knowledge_base do
        rule "ai_sentiment_analysis" do
          priority 20
          on :news_data,
            symbol: satisfies { |s| s && s.length > 0 },
            headline: satisfies { |h| h && h.length > 10 },
            content: satisfies { |c| c && c.length > 50 }

          perform do |facts|
            news = facts.find { |f| f.type == :news_data }
            symbol = news[:symbol]

            # AI-powered sentiment analysis
            sentiment = ai_sys.analyze_sentiment_with_ai(news[:headline], news[:content])

            puts "🤖 AI SENTIMENT ANALYSIS: #{symbol}"
            puts "   Headline: #{news[:headline][0..80]}..."
            puts "   AI Sentiment: #{sentiment[:sentiment]} (#{sentiment[:confidence]}%)"
            puts "   Key Themes: #{sentiment[:themes].join(', ')}"
            puts "   Market Impact: #{sentiment[:market_impact]}"

            # Add sentiment fact to working memory
            ai_sys.kb.fact :ai_sentiment, {
              symbol: symbol,
              sentiment_score: sentiment[:score],
              confidence: sentiment[:confidence],
              themes: sentiment[:themes],
              market_impact: sentiment[:market_impact],
              timestamp: Time.now
            }
          end
        end

        rule "ai_strategy_generation" do
          priority 15
          on :market_conditions,
            volatility: satisfies { |v| v && v > 25 },
            trend: satisfies { |t| t && t.length > 0 }
          on :portfolio_state, cash_ratio: satisfies { |c| c && c > 0.2 }

          perform do |facts|
            market = facts.find { |f| f.type == :market_conditions }
            portfolio = facts.find { |f| f.type == :portfolio_state }

            # Generate AI strategy
            strategy = ai_sys.generate_ai_trading_strategy(market, portfolio)

            puts "🧠 AI TRADING STRATEGY"
            puts "   Market Context: #{market[:trend]} trend, #{market[:volatility]}% volatility"
            puts "   Strategy: #{strategy[:name]}"
            puts "   Rationale: #{strategy[:rationale]}"
            puts "   Actions: #{strategy[:actions].join(', ')}"
            puts "   Risk Level: #{strategy[:risk_level]}"
          end
        end

        rule "dynamic_rule_creation" do
          priority 12
          on :pattern_anomaly,
            pattern_type: satisfies { |p| p && p.length > 0 },
            confidence: satisfies { |c| c && c > 0.8 },
            occurrences: satisfies { |o| o && o > 5 }

          perform do |facts|
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
              @kb.engine.add_rule(dynamic_rule)
              puts "   ✅ Rule added to knowledge base"
            end
          end
        end

        rule "ai_risk_assessment" do
          priority 18
          on :position, unrealized_pnl: satisfies { |pnl| pnl && pnl.abs > 1000 }
          on :market_data, symbol: satisfies { |s| s && s.length > 0 }

          perform do |facts|
            position = facts.find { |f| f.type == :position }
            market_data = facts.find { |f| f.type == :market_data }

            # AI-powered risk analysis
            risk_analysis = ai_sys.analyze_position_risk_with_ai(position, market_data)

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
          end
        end

        rule "ai_explanation_generator" do
          priority 5
          on :trade_recommendation,
            action: satisfies { |a| ["BUY", "SELL", "HOLD"].include?(a) },
            symbol: satisfies { |s| s && s.length > 0 }

          perform do |facts|
            recommendation = facts.find { |f| f.type == :trade_recommendation }

            # Generate natural language explanation
            explanation = ai_sys.generate_trade_explanation(recommendation, facts)

            puts "💬 AI EXPLANATION: #{recommendation[:symbol]} #{recommendation[:action]}"
            puts "   Reasoning: #{explanation[:reasoning]}"
            puts "   Context: #{explanation[:context]}"
            puts "   Confidence: #{explanation[:confidence]}%"
            puts "   Alternative View: #{explanation[:alternative]}"
          end
        end

        rule "ai_pattern_recognition" do
          priority 10
          on :price_history,
            symbol: satisfies { |s| s && s.length > 0 },
            data_points: satisfies { |d| d && d.length >= 30 }

          perform do |facts|
            price_data = facts.find { |f| f.type == :price_history }

            # AI identifies patterns
            patterns = ai_sys.identify_patterns_with_ai(price_data[:data_points])

            if patterns.any?
              puts "📊 AI PATTERN RECOGNITION: #{price_data[:symbol]}"
              patterns.each do |pattern|
                puts "   Pattern: #{pattern[:name]} (#{pattern[:confidence]}%)"
                puts "   Prediction: #{pattern[:prediction]}"
                puts "   Time Horizon: #{pattern[:time_horizon]}"
              end
            end
          end
        end
      end
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

    def build_rule_generation_prompt(anomaly_data)
      <<~PROMPT
        Generate a trading rule specification for this anomaly pattern:

        Pattern Type: #{anomaly_data[:pattern_type]}
        Confidence: #{anomaly_data[:confidence]}
        Occurrences: #{anomaly_data[:occurrences]}

        Return JSON with:
        {
          "name": "rule_name",
          "description": "what this rule does",
          "valid": true|false
        }
      PROMPT
    end

    def create_rule_from_spec(spec)
      # Simplified rule creation - in production would parse spec more thoroughly
      KBS::Rule.new(
        spec[:name],
        conditions: [],
        action: lambda { |facts, bindings| puts "Dynamic rule fired: #{spec[:name]}" }
      )
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
      result = JSON.parse(extract_json(response), symbolize_names: true)
      # Ensure all expected keys exist
      {
        reasoning: result[:reasoning] || result[:explanation] || "No reasoning provided",
        context: result[:context] || "No context provided",
        confidence: result[:confidence] || 50,
        alternative: result[:alternative] || result[:risks]&.join(", ") || "No alternatives provided"
      }
    end

    def parse_pattern_response(response)
      patterns = JSON.parse(extract_json(response), symbolize_names: true)
      # Ensure array format and normalize keys
      patterns = [patterns] unless patterns.is_a?(Array)
      patterns.map do |p|
        {
          name: p[:pattern] || p[:name] || "Unknown Pattern",
          confidence: p[:confidence] || 50,
          prediction: p[:prediction] || p[:description] || "No prediction",
          time_horizon: p[:time_horizon] || "Unknown"
        }
      end
    end

    def parse_risk_analysis(response)
      JSON.parse(extract_json(response), symbolize_names: true)
    end

    def parse_rule_specification(response)
      JSON.parse(extract_json(response), symbolize_names: true)
    end

    def demonstrate_ai_enhancements
      puts "🤖 AI-ENHANCED KNOWLEDGE-BASED SYSTEM"
      puts "=" * 70
      puts "Integrating #{@ai_client.class.name} and #{@mcp_agent.class.name if @mcp_agent}"
      puts "=" * 70

      # Scenario 1: AI Sentiment Analysis
      puts "\n📰 SCENARIO 1: AI-Powered News Sentiment"
      puts "-" * 50
      @kb.reset

      @kb.fact :news_data, {
        symbol: "AAPL",
        headline: "Apple Reports Record Q4 Earnings, Beats Expectations by 15%",
        content: "Apple Inc. announced exceptional fourth quarter results today, with revenue growing 12% year-over-year to $94.9 billion. iPhone sales exceeded analysts' expectations, driven by strong demand for the iPhone 15 Pro models. The company also announced a new $90 billion share buyback program and increased its dividend by 4%. CEO Tim Cook expressed optimism about the AI integration roadmap and services growth trajectory.",
        published_at: Time.now
      }
      @kb.run

      # Scenario 2: AI Strategy Generation
      puts "\n🧠 SCENARIO 2: AI Trading Strategy Generation"
      puts "-" * 50
      @kb.reset

      @kb.fact :market_conditions, {
        volatility: 28.5,
        trend: "sideways",
        sector_rotation: "technology_to_healthcare"
      }

      @kb.fact :portfolio_state, {
        cash_ratio: 0.25,
        largest_position: "AAPL",
        sector_concentration: 0.45
      }
      @kb.run

      # Scenario 3: AI Risk Assessment
      puts "\n⚠️  SCENARIO 3: AI Risk Assessment"
      puts "-" * 50
      @kb.reset

      @kb.fact :position, {
        symbol: "TSLA",
        shares: 100,
        entry_price: 250.00,
        current_price: 235.00,
        unrealized_pnl: -1500
      }

      @kb.fact :market_data, {
        symbol: "TSLA",
        volatility: 45.2,
        beta: 2.1,
        sector: "Consumer Discretionary"
      }
      @kb.run

      # Scenario 4: Trade Explanation
      puts "\n💬 SCENARIO 4: AI Trade Explanation"
      puts "-" * 50
      @kb.reset

      @kb.fact :trade_recommendation, {
        symbol: "GOOGL",
        action: "BUY",
        quantity: 50,
        confidence: 85
      }

      @kb.fact :technical_analysis, {
        symbol: "GOOGL",
        rsi: 35,
        moving_average_signal: "golden_cross",
        volume_trend: "increasing"
      }
      @kb.run

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
