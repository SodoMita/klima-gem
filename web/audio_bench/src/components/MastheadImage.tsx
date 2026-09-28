"use client";

/**
 * Masthead photograph. Client-side only so a failed load degrades to the
 * designed gradient surface underneath instead of leaving a hole.
 */
export default function MastheadImage() {
  return (
    <img
      src="/images/chassis.jpg"
      alt="Warm grey anodised studio component with a dark instrument face and one orange switch"
      className="absolute inset-0 h-full w-full object-cover object-right"
      onError={(e) => {
        e.currentTarget.style.display = "none";
      }}
    />
  );
}
