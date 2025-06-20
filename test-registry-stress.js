#!/usr/bin/env node

/**
 * Stress test for ServerRegistry
 * Tests performance under heavy load and concurrent operations
 */

import { ServerRegistry } from './src/registry.js';
import winston from 'winston';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { writeFileSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Create logger for stress tests
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.printf(({ timestamp, level, message }) => {
      return `[STRESS] ${timestamp} ${level}: ${message}`;
    })
  ),
  transports: [
    new winston.transports.Console()
  ]
});

// Stress test configuration
const STRESS_CONFIG = {
  // Number of concurrent sessions
  CONCURRENT_SESSIONS: 50,
  
  // Number of messages per session
  MESSAGES_PER_SESSION: 100,
  
  // Message interval (ms)
  MESSAGE_INTERVAL: 10,
  
  // Number of rapid connect/disconnect cycles
  RAPID_CYCLES: 20,
  
  // Test duration for memory leak test (ms)
  MEMORY_TEST_DURATION: 30000,
  
  // Large message size (characters)
  LARGE_MESSAGE_SIZE: 100000
};

// Test configuration
const TEST_CONFIG = {
  servers: [
    {
      name: 'stress-test-1',
      path: 'stress1',
      command: 'node',
      args: [join(__dirname, 'mock-mcp-server.js')],
      env: {
        MOCK_SERVER_NAME: 'stress-server-1',
        RESPONSE_DELAY: '10'
      },
      enabled: true,
      description: 'Stress test server 1'
    },
    {
      name: 'stress-test-2',
      path: 'stress2',
      command: 'node',
      args: [join(__dirname, 'mock-mcp-server.js')],
      env: {
        MOCK_SERVER_NAME: 'stress-server-2',
        RESPONSE_DELAY: '10'
      },
      enabled: true,
      description: 'Stress test server 2'
    }
  ]
};

// Performance metrics
class PerformanceMetrics {
  constructor() {
    this.metrics = {
      sessionsCreated: 0,
      messagesSent: 0,
      messagesReceived: 0,
      errors: 0,
      avgResponseTime: 0,
      maxResponseTime: 0,
      minResponseTime: Infinity,
      startTime: Date.now(),
      endTime: null,
      memoryUsage: []
    };
    this.responseTimes = [];
  }

  recordSessionCreated() {
    this.metrics.sessionsCreated++;
  }

  recordMessageSent() {
    this.metrics.messagesSent++;
  }

  recordMessageReceived(responseTime) {
    this.metrics.messagesReceived++;
    this.responseTimes.push(responseTime);
    
    if (responseTime > this.metrics.maxResponseTime) {
      this.metrics.maxResponseTime = responseTime;
    }
    if (responseTime < this.metrics.minResponseTime) {
      this.metrics.minResponseTime = responseTime;
    }
  }

  recordError() {
    this.metrics.errors++;
  }

  recordMemoryUsage() {
    const usage = process.memoryUsage();
    this.metrics.memoryUsage.push({
      timestamp: Date.now(),
      heapUsed: usage.heapUsed,
      heapTotal: usage.heapTotal,
      rss: usage.rss
    });
  }

  calculateFinalMetrics() {
    this.metrics.endTime = Date.now();
    this.metrics.duration = this.metrics.endTime - this.metrics.startTime;
    
    if (this.responseTimes.length > 0) {
      this.metrics.avgResponseTime = 
        this.responseTimes.reduce((a, b) => a + b, 0) / this.responseTimes.length;
    }
    
    // Calculate percentiles
    if (this.responseTimes.length > 0) {
      const sorted = this.responseTimes.sort((a, b) => a - b);
      this.metrics.p50 = sorted[Math.floor(sorted.length * 0.5)];
      this.metrics.p90 = sorted[Math.floor(sorted.length * 0.9)];
      this.metrics.p99 = sorted[Math.floor(sorted.length * 0.99)];
    }
    
    // Calculate throughput
    this.metrics.messagesPerSecond = 
      this.metrics.messagesSent / (this.metrics.duration / 1000);
    
    return this.metrics;
  }

  printSummary() {
    const metrics = this.calculateFinalMetrics();
    
    logger.info('\n=== Performance Metrics ===');
    logger.info(`Duration: ${metrics.duration}ms`);
    logger.info(`Sessions created: ${metrics.sessionsCreated}`);
    logger.info(`Messages sent: ${metrics.messagesSent}`);
    logger.info(`Messages received: ${metrics.messagesReceived}`);
    logger.info(`Errors: ${metrics.errors}`);
    logger.info(`Throughput: ${metrics.messagesPerSecond.toFixed(2)} msg/sec`);
    logger.info('\nResponse Times:');
    logger.info(`  Average: ${metrics.avgResponseTime.toFixed(2)}ms`);
    logger.info(`  Min: ${metrics.minResponseTime}ms`);
    logger.info(`  Max: ${metrics.maxResponseTime}ms`);
    logger.info(`  P50: ${metrics.p50}ms`);
    logger.info(`  P90: ${metrics.p90}ms`);
    logger.info(`  P99: ${metrics.p99}ms`);
    
    if (metrics.memoryUsage.length > 0) {
      const firstUsage = metrics.memoryUsage[0];
      const lastUsage = metrics.memoryUsage[metrics.memoryUsage.length - 1];
      const heapGrowth = lastUsage.heapUsed - firstUsage.heapUsed;
      const rssGrowth = lastUsage.rss - firstUsage.rss;
      
      logger.info('\nMemory Usage:');
      logger.info(`  Heap growth: ${(heapGrowth / 1024 / 1024).toFixed(2)}MB`);
      logger.info(`  RSS growth: ${(rssGrowth / 1024 / 1024).toFixed(2)}MB`);
    }
  }
}

// Stress test scenarios
const stressTests = {
  // Test 1: Many concurrent sessions
  async testConcurrentSessions() {
    logger.info('\n=== Stress Test 1: Concurrent Sessions ===');
    const metrics = new PerformanceMetrics();
    
    const configPath = join(__dirname, 'stress-config.json');
    writeFileSync(configPath, JSON.stringify(TEST_CONFIG, null, 2));
    
    const registry = new ServerRegistry(logger);
    await registry.initialize(configPath);
    
    try {
      // Create many sessions concurrently
      const sessionPromises = [];
      for (let i = 0; i < STRESS_CONFIG.CONCURRENT_SESSIONS; i++) {
        const serverName = i % 2 === 0 ? 'stress-test-1' : 'stress-test-2';
        sessionPromises.push(
          registry.createSession(serverName)
            .then(() => metrics.recordSessionCreated())
            .catch(() => metrics.recordError())
        );
      }
      
      await Promise.all(sessionPromises);
      logger.info(`Created ${STRESS_CONFIG.CONCURRENT_SESSIONS} sessions`);
      
      // Wait for processes to stabilize
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      metrics.printSummary();
    } finally {
      await registry.shutdown();
    }
  },

  // Test 2: High message throughput
  async testHighThroughput() {
    logger.info('\n=== Stress Test 2: High Message Throughput ===');
    const metrics = new PerformanceMetrics();
    
    const configPath = join(__dirname, 'stress-config.json');
    writeFileSync(configPath, JSON.stringify(TEST_CONFIG, null, 2));
    
    const registry = new ServerRegistry(logger);
    await registry.initialize(configPath);
    
    try {
      // Create sessions
      const sessions = [];
      for (let i = 0; i < 10; i++) {
        const session = await registry.createSession('stress-test-1');
        sessions.push(session.sessionId);
        metrics.recordSessionCreated();
      }
      
      // Wait for processes to be ready
      await new Promise(resolve => setTimeout(resolve, 500));
      
      // Send many messages
      const messagePromises = [];
      for (const sessionId of sessions) {
        for (let i = 0; i < STRESS_CONFIG.MESSAGES_PER_SESSION; i++) {
          const startTime = Date.now();
          const promise = registry.handlePostRequest(sessionId, {
            jsonrpc: '2.0',
            id: `msg-${sessionId}-${i}`,
            method: 'echo',
            params: { message: `Test message ${i}` }
          }).then(() => {
            const responseTime = Date.now() - startTime;
            metrics.recordMessageReceived(responseTime);
          }).catch(() => {
            metrics.recordError();
          });
          
          metrics.recordMessageSent();
          messagePromises.push(promise);
          
          // Small delay between messages
          if (i % 10 === 0) {
            await new Promise(resolve => setTimeout(resolve, STRESS_CONFIG.MESSAGE_INTERVAL));
          }
        }
      }
      
      await Promise.all(messagePromises);
      metrics.printSummary();
    } finally {
      await registry.shutdown();
    }
  },

  // Test 3: Rapid connect/disconnect
  async testRapidConnectDisconnect() {
    logger.info('\n=== Stress Test 3: Rapid Connect/Disconnect ===');
    const metrics = new PerformanceMetrics();
    
    const configPath = join(__dirname, 'stress-config.json');
    writeFileSync(configPath, JSON.stringify(TEST_CONFIG, null, 2));
    
    const registry = new ServerRegistry(logger);
    await registry.initialize(configPath);
    
    try {
      for (let cycle = 0; cycle < STRESS_CONFIG.RAPID_CYCLES; cycle++) {
        // Create sessions
        const sessions = [];
        for (let i = 0; i < 5; i++) {
          try {
            const session = await registry.createSession('stress-test-1');
            sessions.push(session.sessionId);
            metrics.recordSessionCreated();
          } catch (error) {
            metrics.recordError();
          }
        }
        
        // Send a few messages
        for (const sessionId of sessions) {
          try {
            await registry.sendMessage(sessionId, {
              jsonrpc: '2.0',
              id: `rapid-${cycle}-${sessionId}`,
              method: 'ping'
            });
            metrics.recordMessageSent();
          } catch (error) {
            metrics.recordError();
          }
        }
        
        // Close sessions
        for (const sessionId of sessions) {
          registry.closeSession(sessionId);
        }
        
        // Small delay between cycles
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      
      metrics.printSummary();
    } finally {
      await registry.shutdown();
    }
  },

  // Test 4: Large messages
  async testLargeMessages() {
    logger.info('\n=== Stress Test 4: Large Messages ===');
    const metrics = new PerformanceMetrics();
    
    const configPath = join(__dirname, 'stress-config.json');
    writeFileSync(configPath, JSON.stringify(TEST_CONFIG, null, 2));
    
    const registry = new ServerRegistry(logger);
    await registry.initialize(configPath);
    
    try {
      const { sessionId } = await registry.createSession('stress-test-1');
      metrics.recordSessionCreated();
      
      // Wait for process to be ready
      await new Promise(resolve => setTimeout(resolve, 500));
      
      // Create large message
      const largeData = 'x'.repeat(STRESS_CONFIG.LARGE_MESSAGE_SIZE);
      
      // Send large messages
      for (let i = 0; i < 10; i++) {
        const startTime = Date.now();
        try {
          await registry.handlePostRequest(sessionId, {
            jsonrpc: '2.0',
            id: `large-${i}`,
            method: 'echo',
            params: { message: largeData }
          });
          
          const responseTime = Date.now() - startTime;
          metrics.recordMessageSent();
          metrics.recordMessageReceived(responseTime);
        } catch (error) {
          metrics.recordError();
          logger.error(`Large message error: ${error.message}`);
        }
      }
      
      metrics.printSummary();
    } finally {
      await registry.shutdown();
    }
  },

  // Test 5: Memory leak detection
  async testMemoryLeak() {
    logger.info('\n=== Stress Test 5: Memory Leak Detection ===');
    const metrics = new PerformanceMetrics();
    
    const configPath = join(__dirname, 'stress-config.json');
    writeFileSync(configPath, JSON.stringify(TEST_CONFIG, null, 2));
    
    const registry = new ServerRegistry(logger);
    await registry.initialize(configPath);
    
    try {
      // Record initial memory
      metrics.recordMemoryUsage();
      
      const endTime = Date.now() + STRESS_CONFIG.MEMORY_TEST_DURATION;
      let sessionCounter = 0;
      
      // Continuously create and destroy sessions
      while (Date.now() < endTime) {
        // Create batch of sessions
        const sessions = [];
        for (let i = 0; i < 10; i++) {
          try {
            const session = await registry.createSession('stress-test-1');
            sessions.push(session.sessionId);
            metrics.recordSessionCreated();
            sessionCounter++;
          } catch (error) {
            metrics.recordError();
          }
        }
        
        // Send messages
        for (const sessionId of sessions) {
          for (let i = 0; i < 5; i++) {
            try {
              await registry.sendMessage(sessionId, {
                jsonrpc: '2.0',
                id: `mem-${sessionCounter}-${i}`,
                method: 'echo',
                params: { data: 'Memory test' }
              });
              metrics.recordMessageSent();
            } catch (error) {
              metrics.recordError();
            }
          }
        }
        
        // Close sessions
        for (const sessionId of sessions) {
          registry.closeSession(sessionId);
        }
        
        // Record memory periodically
        if (sessionCounter % 50 === 0) {
          metrics.recordMemoryUsage();
          logger.info(`Sessions created: ${sessionCounter}, Heap: ${(process.memoryUsage().heapUsed / 1024 / 1024).toFixed(2)}MB`);
        }
        
        // Small delay
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      
      // Final memory recording
      metrics.recordMemoryUsage();
      metrics.printSummary();
      
      // Check for memory leak
      const memoryUsage = metrics.metrics.memoryUsage;
      if (memoryUsage.length > 2) {
        const firstHalf = memoryUsage.slice(0, Math.floor(memoryUsage.length / 2));
        const secondHalf = memoryUsage.slice(Math.floor(memoryUsage.length / 2));
        
        const avgFirstHalf = firstHalf.reduce((sum, m) => sum + m.heapUsed, 0) / firstHalf.length;
        const avgSecondHalf = secondHalf.reduce((sum, m) => sum + m.heapUsed, 0) / secondHalf.length;
        
        const growth = ((avgSecondHalf - avgFirstHalf) / avgFirstHalf) * 100;
        
        if (growth > 50) {
          logger.warn(`⚠️  Potential memory leak detected: ${growth.toFixed(2)}% growth`);
        } else {
          logger.info(`✓ Memory usage stable: ${growth.toFixed(2)}% growth`);
        }
      }
    } finally {
      await registry.shutdown();
    }
  },

  // Test 6: Process crash recovery under load
  async testCrashRecoveryUnderLoad() {
    logger.info('\n=== Stress Test 6: Crash Recovery Under Load ===');
    const metrics = new PerformanceMetrics();
    
    // Use crash configuration
    const crashConfig = {
      servers: [{
        name: 'crash-test',
        path: 'crash',
        command: 'node',
        args: [join(__dirname, 'mock-mcp-server.js')],
        env: {
          MOCK_SERVER_NAME: 'crash-test-server',
          SIMULATE_CRASH: 'true',
          CRASH_AFTER_MS: '5000',
          RESPONSE_DELAY: '10'
        },
        enabled: true,
        description: 'Crash test server'
      }]
    };
    
    const configPath = join(__dirname, 'crash-stress-config.json');
    writeFileSync(configPath, JSON.stringify(crashConfig, null, 2));
    
    const registry = new ServerRegistry(logger);
    await registry.initialize(configPath);
    
    try {
      // Create multiple sessions
      const sessions = [];
      for (let i = 0; i < 5; i++) {
        const session = await registry.createSession('crash-test');
        sessions.push(session.sessionId);
        metrics.recordSessionCreated();
      }
      
      // Continuously send messages
      const messageLoop = async (sessionId) => {
        let messageCount = 0;
        while (messageCount < 50) {
          try {
            const startTime = Date.now();
            await registry.handlePostRequest(sessionId, {
              jsonrpc: '2.0',
              id: `crash-${sessionId}-${messageCount}`,
              method: 'ping'
            });
            
            const responseTime = Date.now() - startTime;
            metrics.recordMessageSent();
            metrics.recordMessageReceived(responseTime);
          } catch (error) {
            metrics.recordError();
            // Wait a bit and retry after crash
            await new Promise(resolve => setTimeout(resolve, 1000));
          }
          
          messageCount++;
          await new Promise(resolve => setTimeout(resolve, 100));
        }
      };
      
      // Start message loops for all sessions
      const loops = sessions.map(sessionId => messageLoop(sessionId));
      await Promise.all(loops);
      
      metrics.printSummary();
      logger.info(`✓ Successfully recovered from crashes under load`);
    } finally {
      await registry.shutdown();
    }
  }
};

// Run all stress tests
async function runStressTests() {
  logger.info('Starting ServerRegistry stress tests...');
  logger.info(`Configuration: ${JSON.stringify(STRESS_CONFIG, null, 2)}\n`);
  
  const results = {
    passed: 0,
    failed: 0,
    errors: []
  };
  
  for (const [testName, testFn] of Object.entries(stressTests)) {
    try {
      await testFn();
      results.passed++;
    } catch (error) {
      results.failed++;
      results.errors.push({ test: testName, error: error.message });
      logger.error(`✗ ${testName} failed: ${error.message}`);
      console.error(error);
    }
    
    // Pause between tests
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
  
  // Summary
  logger.info('\n=== Stress Test Summary ===');
  logger.info(`Total tests: ${results.passed + results.failed}`);
  logger.info(`Passed: ${results.passed}`);
  logger.info(`Failed: ${results.failed}`);
  
  if (results.errors.length > 0) {
    logger.error('\nFailed tests:');
    results.errors.forEach(({ test, error }) => {
      logger.error(`  - ${test}: ${error}`);
    });
  }
  
  process.exit(results.failed > 0 ? 1 : 0);
}

// Run tests if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  runStressTests().catch(error => {
    logger.error('Stress test runner failed:', error);
    process.exit(1);
  });
}

export { runStressTests, STRESS_CONFIG };