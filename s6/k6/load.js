import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    rps: {
      executor: 'constant-arrival-rate',
      rate: 50,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 20,
      maxVUs: 50,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<300'],
    http_req_failed: ['rate<0.01'],
  },
};

export default () => {
  // Si ton Ingress écoute en NodePort 30443, mets : https://workshop.local:30443/...
  const res = http.get('https://workshop.local/api/status/200', { timeout: '5s' });
  check(res, { 'status 200': (r) => r.status === 200 });
};
