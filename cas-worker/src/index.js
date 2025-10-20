import { AutoRouter } from 'itty-router';
import { handleGetValue, handleSave } from './cas.js';
import { handleKeyValueGet, handleKeyValuePut } from './key-value.js';

const router = AutoRouter();

// KeyValue endpoints - more specific route first
router.put('/api/cache/keyvalue/:cas_id', handleKeyValueGet);
router.put('/api/cache/keyvalue', handleKeyValuePut);

// CAS endpoints with query parameters
router.get('/api/cache/cas/:id', handleGetValue);
router.post('/api/cache/cas/:id', handleSave);

// Export the router directly (AutoRouter handles 404s and errors automatically)
export default router;
