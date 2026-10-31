import { createServer } from 'node:http';

createServer((request, response) => {
  response.setHeader('content-type', 'text/plain; charset=utf-8');

  if (request.url === '/health') {
    response.end('healthy');
    return;
  }

  response.end('hello from mas');
}).listen(8081, '0.0.0.0', () => {
  console.log('mas listening on 8081');
});
