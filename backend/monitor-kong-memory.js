#!/usr/bin/env node
/**
 * Kong Memory Monitoring Script
 * Monitors Kong Gateway memory usage and mapping store statistics
 */

const axios = require('axios');

async function monitorKongMemory() {
  console.log('📊 Kong Gateway Memory Monitor');
  console.log('===============================');
  
  try {
    const response = await axios.get('http://localhost:8001/status');
    const status = response.data;
    
    console.log('\n🧠 Memory Usage:');
    console.log('Kong Core Cache:', status.memory.lua_shared_dicts.kong_core_db_cache.allocated_slabs);
    console.log('Kong Cache:', status.memory.lua_shared_dicts.kong_db_cache.allocated_slabs);
    
    console.log('\n⚡ Workers:');
    status.memory.workers_lua_vms.forEach((worker, index) => {
      console.log(`Worker ${index + 1}: ${worker.http_allocated_gc}`);
    });
    
    console.log('\n📈 Connection Stats:');
    console.log(`Active: ${status.server.connections_active}`);
    console.log(`Total Requests: ${status.server.total_requests}`);
    
    // AWS Masker 관련 로그는 Kong 로그에서 확인
    console.log('\n💡 AWS Masker 매핑 정보는 Kong 로그를 확인하세요:');
    console.log('docker-compose logs kong | grep "mapping"');
    
  } catch (error) {
    console.error('❌ Kong 상태 조회 실패:', error.message);
  }
}

// 주기적 모니터링 (30초마다)
setInterval(() => {
  console.log('\n' + '='.repeat(50));
  console.log(new Date().toLocaleString());
  monitorKongMemory();
}, 30000);

// 첫 실행
monitorKongMemory();