import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import '../helpers.dart';

void main() {
  group("Operations and security schemes", () {
    APIDocument doc;

    setUpAll(() async {
      doc = await Application.document(TestChannel, new ApplicationOptions(), {"name": "Test", "version": "1.0"});
    });

    test("AuthServer documents components", () {
      final schemes = doc.components.securitySchemes;

      expect(schemes.length, 2);
      expect(schemes["oauth2"].type, APISecuritySchemeType.oauth2);
      expect(schemes["oauth2-client-authentication"].type, APISecuritySchemeType.http);
      expect(schemes["oauth2-client-authentication"].scheme, "basic");
    });

    test("Basic Authorizer adds oauth2 client authentication to operations for all paths", () {
      final noVarPath = doc.paths["/basic"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements, {"oauth2-client-authentication": []});
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements, {"oauth2-client-authentication": []});

      final varPath = doc.paths["/basic/{id}"];
      expect(varPath.operations.length, 1);
      expect(varPath.operations["get"].security.length, 1);
      expect(varPath.operations["get"].security.first.requirements, {"oauth2-client-authentication": []});
    });

    test("No scope bearer authorizer adds oauth2 authentication to operations", () {
      final noVarPath = doc.paths["/bearer-no-scope"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements, {"oauth2": []});
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements, {"oauth2": []});
    });

    test("Scoped bearer authorizer adds oauth2 authentication to operations w/ scope", () {
      final noVarPath = doc.paths["/bearer-scope"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements, {
        "oauth2": ["scope"]
      });
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements, {
        "oauth2": ["scope"]
      });
    });
  });

  group("Controller Registration and Scopes", () {
    test("If no controllers added to channel, do not support have flows for oauth2 security type", () async {
      final doc = await Application.document(TestChannel, new ApplicationOptions(), {"name": "Test", "version": "1.0"});
      expect(doc.components.securitySchemes["oauth2"].flows, {});
    });

    test("If only AuthController added to channel, do not support auth code flow", () async {
      final doc = await Application.document(AuthControllerOnlyChannel, new ApplicationOptions(), {"name": "Test", "version": "1.0"});
      expect(doc.components.securitySchemes["oauth2"].flows["password"].refreshURL, new Uri(path: "/auth/token"));
      expect(doc.components.securitySchemes["oauth2"].flows["password"].tokenURL, new Uri(path: "/auth/token"));
      expect(doc.components.securitySchemes["oauth2"].flows["password"].authorizationURL, isNull);
      expect(doc.components.securitySchemes["oauth2"].flows["password"].scopes, {});
    });

    test("If both AuthController and AuthCodeController added to channel, support both flows and have appropriate urls", () async {
      final doc = await Application.document(ScopedControllerChannel, new ApplicationOptions(), {"name": "Test", "version": "1.0"});
      expect(doc.components.securitySchemes["oauth2"].flows["password"].refreshURL, new Uri(path: "/auth/token"));
      expect(doc.components.securitySchemes["oauth2"].flows["password"].tokenURL, new Uri(path: "/auth/token"));
      expect(doc.components.securitySchemes["oauth2"].flows["password"].authorizationURL, isNull);

      expect(doc.components.securitySchemes["oauth2"].flows["authorizationCode"].refreshURL, new Uri(path: "/auth/token"));
      expect(doc.components.securitySchemes["oauth2"].flows["authorizationCode"].tokenURL, new Uri(path: "/auth/token"));
      expect(doc.components.securitySchemes["oauth2"].flows["authorizationCode"].authorizationURL, new Uri(path: "/auth/code"));
    });

    test("Referenced scopes for supported flows are available in oauth2 flow map", () async {
      final doc = await Application.document(ScopedControllerChannel, new ApplicationOptions(), {"name": "Test", "version": "1.0"});
      expect(doc.components.securitySchemes["oauth2"].flows["password"].scopes, {"scope1": "", "scope2": ""});
      expect(doc.components.securitySchemes["oauth2"].flows["authorizationCode"].scopes, {"scope1": "", "scope2": ""});
    });
  });

}

class TestChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    authServer = new AuthServer(new InMemoryAuthStorage());
  }

  @override
  Controller get entryPoint {
    // Note that AuthCodeController/AuthController are not added to channel.
    // This supports a test in 'Controller Registration and Scopes'.

    final router = new Router();
    router.route("/basic/[:id]").link(() => new Authorizer.basic(authServer)).link(() => new DocumentedController());
    router
        .route("/bearer-no-scope")
        .link(() => new Authorizer.bearer(authServer))
        .link(() => new DocumentedController());
    router
        .route("/bearer-scope")
        .link(() => new Authorizer.bearer(authServer, scopes: ["scope"]))
        .link(() => new DocumentedController());
    return router;
  }
}

class DocumentedController extends Controller {
  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext components, String route, APIPath path) {
    if (path.containsPathParameters([])) {
      return {
        "get": new APIOperation("get/0", {
          "200": new APIResponse("get/0-200", content: {"application/json": new APIMediaType(schema: new APISchemaObject.string())})
        }),
        "post": new APIOperation("post/0", {
          "200": new APIResponse("post/0-200", content: {"application/json": new APIMediaType(schema: new APISchemaObject.string())})
        })
      };
    }

    return {
      "get": new APIOperation("get/1", {
        "200": new APIResponse("get/1-200", content: {"application/json": new APIMediaType(schema: new APISchemaObject.string())})
      })
    };
  }
}

class AuthControllerOnlyChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    authServer = new AuthServer(new InMemoryAuthStorage());
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/auth/token").link(() => new AuthController(authServer));
    return router;
  }
}

class ScopedControllerChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    authServer = new AuthServer(new InMemoryAuthStorage());
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/auth/token").link(() => new AuthController(authServer));
    router.route("/auth/code").link(() => new AuthCodeController(authServer));
    router
        .route("/r1")
        .link(() => new Authorizer.bearer(authServer, scopes: ["scope1"]))
        .link(() => new DocumentedController());
    router
        .route("/r2")
        .link(() => new Authorizer.bearer(authServer, scopes: ["scope1", "scope2"]))
        .link(() => new DocumentedController());

    router
        .route("/r3")
        .link(() => new Authorizer.bearer(authServer))
        .link(() => new DocumentedController());
    return router;
  }
}