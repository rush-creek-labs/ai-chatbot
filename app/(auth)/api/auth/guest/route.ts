import { NextResponse } from "next/server";
import { auth, signIn } from "@/app/(auth)/auth";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const redirectUrl = searchParams.get("redirectUrl") || "/";

  // Use the same auth() function that the rest of the app uses
  const session = await auth();

  if (session) {
    // Use AUTH_URL for redirects to avoid internal hostname (0.0.0.0:3000)
    const baseUrl = process.env.AUTH_URL || request.url;
    return NextResponse.redirect(new URL("/", baseUrl));
  }

  return signIn("guest", { redirect: true, redirectTo: redirectUrl });
}
