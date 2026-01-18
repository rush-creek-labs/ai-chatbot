import { type NextRequest, NextResponse } from "next/server";
import { getToken } from "next-auth/jwt";
import { guestRegex } from "./lib/constants";

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  /*
   * Playwright starts the dev server and requires a 200 status to
   * begin the tests, so this ensures that the tests can start
   */
  if (pathname.startsWith("/ping")) {
    return new Response("pong", { status: 200 });
  }

  // Allow auth and health check endpoints without authentication
  if (pathname.startsWith("/api/auth") || pathname.startsWith("/api/health")) {
    return NextResponse.next();
  }

  // Determine if we should use secure cookies
  // When AUTH_URL is set (e.g., CloudFront), use its protocol as the source of truth
  // because CloudFront sets x-forwarded-proto to the origin protocol (http), not the viewer protocol
  const authUrl = process.env.AUTH_URL;
  const forwardedProto = request.headers.get("x-forwarded-proto");
  const isHttps = authUrl?.startsWith("https://") ||
                  forwardedProto === "https" ||
                  request.nextUrl.protocol === "https:";

  const token = await getToken({
    req: request,
    secret: process.env.AUTH_SECRET,
    secureCookie: isHttps,
  });

  if (!token) {
    // Build the external URL using AUTH_URL (most reliable for CloudFront/ALB setups)
    // CloudFront doesn't forward x-forwarded-host, and Host header points to ALB
    if (authUrl) {
      // Use AUTH_URL as the canonical external URL
      const baseUrl = authUrl.replace(/\/$/, ""); // Remove trailing slash if present
      const externalUrl = `${baseUrl}${pathname}${request.nextUrl.search}`;
      const redirectUrl = encodeURIComponent(externalUrl);

      return NextResponse.redirect(
        new URL(`/api/auth/guest?redirectUrl=${redirectUrl}`, baseUrl)
      );
    }

    // Fallback: try forwarded headers (for non-CloudFront setups)
    const forwardedHost = request.headers.get("x-forwarded-host");
    const host = forwardedHost || request.nextUrl.host;
    const protocol = forwardedProto || "http";
    const externalUrl = `${protocol}://${host}${pathname}${request.nextUrl.search}`;
    const redirectUrl = encodeURIComponent(externalUrl);
    const baseUrl = `${protocol}://${host}`;

    return NextResponse.redirect(
      new URL(`/api/auth/guest?redirectUrl=${redirectUrl}`, baseUrl)
    );
  }

  const isGuest = guestRegex.test(token?.email ?? "");

  if (token && !isGuest && ["/login", "/register"].includes(pathname)) {
    if (authUrl) {
      return NextResponse.redirect(new URL("/", authUrl));
    }
    const forwardedHost = request.headers.get("x-forwarded-host");
    const host = forwardedHost || request.nextUrl.host;
    const protocol = forwardedProto || "http";
    return NextResponse.redirect(new URL("/", `${protocol}://${host}`));
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    "/",
    "/chat/:id",
    "/api/:path*",
    "/login",
    "/register",

    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico, sitemap.xml, robots.txt (metadata files)
     */
    "/((?!_next/static|_next/image|favicon.ico|sitemap.xml|robots.txt).*)",
  ],
};
