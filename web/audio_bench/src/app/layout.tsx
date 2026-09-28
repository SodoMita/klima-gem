import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
  title: "Klima Gem — Audio Bench · web export playback fix",
  description:
    "Web bench for the Klima Gem audio generator: real ag_dubstep.c output baked at 48000 Hz, sample-accurate Web Audio scheduling, and the diagnosis of the broken GitHub Pages playback.",
};

const fonts =
  "https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700;800&family=IBM+Plex+Mono:wght@400;500;600&display=swap";

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link rel="stylesheet" href={fonts} />
      </head>
      <body className="bg-paper text-ink antialiased">{children}</body>
    </html>
  );
}
