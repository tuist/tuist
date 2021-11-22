import React from 'react';
import ReactDOM from 'react-dom';
import RootStore from "../stores/RootStore";
import App from '@/components/App';

const store = new RootStore();
ReactDOM.render(<App />, document.getElementById('root'));
