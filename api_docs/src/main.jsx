import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '@radix-ui/themes/styles.css';
import 'prismjs/themes/prism-tomorrow.css';
import { Theme } from '@radix-ui/themes';
import App from './App.jsx';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <Theme appearance="dark" accentColor="gray" grayColor="slate" panelBackground="translucent" radius="medium">
      <App />
    </Theme>
  </StrictMode>
);
