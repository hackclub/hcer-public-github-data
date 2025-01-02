export function checkAuth(req: Request): boolean {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return false;

  const adminPassword = process.env.ADMIN_PASSWORD;
  if (!adminPassword) {
    console.error('ADMIN_PASSWORD environment variable not set');
    return false;
  }

  // Basic auth format: "Basic base64(username:password)"
  const [type, credentials] = authHeader.split(' ');
  if (type !== 'Basic') return false;

  const decoded = atob(credentials);
  const [username, password] = decoded.split(':');

  return password === adminPassword;
}

export function requireAuth(req: Request): Response | null {
  if (!checkAuth(req)) {
    return new Response('Unauthorized', {
      status: 401,
      headers: {
        'WWW-Authenticate': 'Basic realm="Admin Area"'
      }
    });
  }
  return null;
} 