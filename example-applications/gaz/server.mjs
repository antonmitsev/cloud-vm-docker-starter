import { createServer } from 'node:http';

createServer((request, response) => {
  response.setHeader('content-type', 'text/plain; charset=utf-8');

  if (request.url === '/health') {
    response.end('healthy');
    return;
  }

  response.end('hello from gaz');
}).listen(8080, '0.0.0.0', () => {
  console.log('gaz listening on 8080');
});
