"use client";

/**
 * AWS DEPLOYMENT: Simplified to theme-only toggle
 * Original functionality included:
 * - User avatar from avatar.vercel.sh (broken - VPC blocks external URLs)
 * - Guest detection and display
 * - Login/logout dropdown item
 *
 * Now only provides theme toggle functionality.
 */

import { Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";

export function SidebarUserNav() {
  const { setTheme, resolvedTheme } = useTheme();

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <SidebarMenuButton
              className="h-10 bg-background data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
              data-testid="theme-toggle-button"
            >
              {resolvedTheme === "dark" ? (
                <Moon className="size-5" />
              ) : (
                <Sun className="size-5" />
              )}
              <span>Theme</span>
            </SidebarMenuButton>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            className="w-(--radix-popper-anchor-width)"
            data-testid="theme-menu"
            side="top"
          >
            <DropdownMenuItem
              className="cursor-pointer"
              data-testid="theme-light"
              onSelect={() => setTheme("light")}
            >
              <Sun className="mr-2 size-4" />
              Light
            </DropdownMenuItem>
            <DropdownMenuItem
              className="cursor-pointer"
              data-testid="theme-dark"
              onSelect={() => setTheme("dark")}
            >
              <Moon className="mr-2 size-4" />
              Dark
            </DropdownMenuItem>
            <DropdownMenuItem
              className="cursor-pointer"
              data-testid="theme-system"
              onSelect={() => setTheme("system")}
            >
              System
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  );
}
