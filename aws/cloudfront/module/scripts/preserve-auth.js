// Template in the base paths from the manifest
// A comma separated list of base paths
var basePaths = "${base_paths}";
var allBasePaths = basePaths.split(",").sort((a, b) => b.length - a.length);

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