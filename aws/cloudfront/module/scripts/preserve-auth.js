function handler(event) {
  var request = event.request;
  var uri = request.uri;
    
  // Preserve auth header for lambdas and other OAC dependent services
  if (request.headers['authorization']) {
      request.headers['x-forwarded-auth'] = {
          value: request.headers['authorization'].value
      };
  }

  return request;
}