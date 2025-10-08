import { AutoRouter } from 'itty-router';
import { handleGetValue, handleSave } from './cas.js';

const router = AutoRouter();

// CAS endpoints
router.get('/api/projects/:account_handle/:project_handle/cas/:id', handleGetValue);
router.post('/api/projects/:account_handle/:project_handle/cas/:id', handleSave);

// Export the router directly (AutoRouter handles 404s and errors automatically)
export default router;
