import AuthForm from '@/components/auth/AuthForm'

interface LoginPageProps {
  searchParams: Promise<{ redirectTo?: string }>
}

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const { redirectTo } = await searchParams

  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <h1 className="mb-8 text-2xl font-bold tracking-tight text-gray-900">
          Sign in
        </h1>
        <AuthForm mode="login" redirectTo={redirectTo} />
        <p className="mt-6 text-center text-sm text-gray-500">
          No account yet?{' '}
          <a href="/signup" className="font-medium text-indigo-600 hover:text-indigo-500">
            Sign up
          </a>
        </p>
      </div>
    </main>
  )
}
