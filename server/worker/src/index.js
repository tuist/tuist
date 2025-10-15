import { AutoRouter } from 'itty-router';
import { handleGetValue, handleSave } from './cas.js';

const router = AutoRouter();

// CAS endpoints with query parameters
router.get('/api/cas/:id', handleGetValue);
router.post('/api/cas/:id', handleSave);

// Export the router directly (AutoRouter handles 404s and errors automatically)
export default router;
