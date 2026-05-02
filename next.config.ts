import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // Supabase image domain for profile photos (when added)
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: '*.supabase.co',
        port: '',
        pathname: '/storage/v1/object/public/**',
      },
    ],
  },
}

export default nextConfig
