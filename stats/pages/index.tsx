import Head from '../components/head'
import { ProjectIcon, EyeIcon, VersionsIcon } from '@primer/octicons-react'

const Workflows = () => {
  return (
    <div className="mt-10">
      <h1 className="mt-2 mb-8 text-3xl text-center leading-8 font-bold tracking-tight text-gray-900 sm:text-4xl sm:leading-10">
        Workflows
      </h1>
      <p className="text-center prose-lg text-gray-700 my-10">
        Every feature we design starts from the devise of a workflow that maps
        to an user's intent. For example, a user might want to focus on a target
        of a project, or just run the tests of a framework. Those workflows
        translate to commands on Tuist, for example "tuist focus". The metrics
        below reflect the usage of each of the workflows - understanding their
        usage helps us <b>prioritize our efforts</b>:
      </p>
      <div>
        <h3 className="text-lg leading-6 font-medium text-gray-900">
          Last 30 days
        </h3>
        <div className="mt-5 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="px-4 py-5 sm:p-6">
              <div className="flex items-center">
                <div className="flex-shrink-0 bg-blue-500 rounded-md p-3">
                  <ProjectIcon className="text-white" size={24} />
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm leading-5 font-medium text-gray-500 truncate">
                      Projects generated
                    </dt>
                    <dd className="flex items-baseline">
                      <div className="text-2xl leading-8 font-semibold text-gray-900">
                        71897
                      </div>
                      <div className="ml-2 flex items-baseline text-sm leading-5 font-semibold text-green-600">
                        <svg
                          className="self-center flex-shrink-0 h-5 w-5 text-green-500"
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path
                            fillRule="evenodd"
                            d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z"
                            clipRule="evenodd"
                          />
                        </svg>
                        <span className="sr-only">Increased by</span>
                        122
                      </div>
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>
          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="px-4 py-5 sm:p-6">
              <div className="flex items-center">
                <div className="flex-shrink-0 bg-blue-500 rounded-md p-3">
                  <EyeIcon className="text-white" size={24} />
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm leading-5 font-medium text-gray-500 truncate">
                      Focused projects
                    </dt>
                    <dd className="flex items-baseline">
                      <div className="text-2xl leading-8 font-semibold text-gray-900">
                        50922
                      </div>
                      <div className="ml-2 flex items-baseline text-sm leading-5 font-semibold text-green-600">
                        <svg
                          className="self-center flex-shrink-0 h-5 w-5 text-green-500"
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path
                            fillRule="evenodd"
                            d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z"
                            clipRule="evenodd"
                          />
                        </svg>
                        <span className="sr-only">Increased by</span>
                        300
                      </div>
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>
          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="px-4 py-5 sm:p-6">
              <div className="flex items-center">
                <div className="flex-shrink-0 bg-blue-500 rounded-md p-3">
                  <VersionsIcon className="text-white" size={24} />
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm leading-5 font-medium text-gray-500 truncate">
                      Scaffolds
                    </dt>
                    <dd className="flex items-baseline">
                      <div className="text-2xl leading-8 font-semibold text-gray-900">
                        24300
                      </div>
                      <div className="ml-2 flex items-baseline text-sm leading-5 font-semibold text-red-600">
                        <svg
                          className="self-center flex-shrink-0 h-5 w-5 text-red-500"
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path
                            fillRule="evenodd"
                            d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z"
                            clipRule="evenodd"
                          />
                        </svg>
                        <span className="sr-only">Decreased by</span>
                        24
                      </div>
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

const Environment = () => {
  return (
    <div className="mt-10">
      <h1 className="mt-2 mb-8 text-3xl text-center leading-8 font-bold tracking-tight text-gray-900 sm:text-4xl sm:leading-10">
        Environment
      </h1>
      <p className="text-center prose-lg text-gray-700 my-10">
        <b>Where do users use Tuist?</b> If we understand where Tuist runs, we
        know what we are optimizing for and what we can deprecate. For example,
        if Tuist is barely used with Xcode 11.3.1, it might be a good time to
        deprecate its support.
      </p>
      <div>
        <h3 className="text-lg leading-6 font-medium text-gray-900">
          Xcode versions
        </h3>
        <div className="flex flex-col mt-8">
          <div className="-my-2 py-2 overflow-x-auto sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8">
            <div className="align-middle inline-block min-w-full shadow overflow-hidden sm:rounded-lg border-b border-gray-200">
              <table className="min-w-full divide-y divide-gray-200">
                <thead>
                  <tr>
                    <th className="px-6 py-3 bg-gray-50 text-left text-xs leading-4 font-medium text-gray-500 uppercase tracking-wider">
                      Version
                    </th>
                    <th className="px-6 py-3 bg-gray-50 text-left text-xs leading-4 font-medium text-gray-500 uppercase tracking-wider">
                      Usage
                    </th>
                    <th className="px-6 py-3 bg-gray-50" />
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  <tr>
                    <td className="px-6 py-4 whitespace-no-wrap text-sm leading-5 font-medium text-gray-900">
                      Xcode 11.6
                    </td>
                    <td className="px-6 py-4 whitespace-no-wrap text-sm font-semibold leading-5 text-green-600">
                      75%
                    </td>
                  </tr>
                  <tr>
                    <td className="px-6 py-4 whitespace-no-wrap text-sm leading-5 font-medium text-gray-900">
                      Xcode 11.5
                    </td>
                    <td className="px-6 py-4 whitespace-no-wrap text-sm font-semibold leading-5 text-blue-600">
                      15%
                    </td>
                  </tr>
                  <tr>
                    <td className="px-6 py-4 whitespace-no-wrap text-sm leading-5 font-medium text-gray-900">
                      Xcode 11.4
                    </td>
                    <td className="px-6 py-4 whitespace-no-wrap text-sm font-semibold leading-5 text-blue-600">
                      5%
                    </td>
                  </tr>
                  <tr>
                    <td className="px-6 py-4 whitespace-no-wrap text-sm leading-5 font-medium text-gray-900">
                      Xcode 11.3.1
                    </td>
                    <td className="px-6 py-4 whitespace-no-wrap text-sm font-semibold leading-5 text-blue-600">
                      5%
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

const Projects = () => {
  return (
    <div className="mt-10">
      <h1 className="mt-2 mb-8 text-3xl text-center leading-8 font-bold tracking-tight text-gray-900 sm:text-4xl sm:leading-10">
        Projects
      </h1>
      <div>
        <h3 className="text-lg leading-6 font-medium text-gray-900">
          Last 30 days
        </h3>
        <div className="mt-5 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="px-4 py-5 sm:p-6">
              <div className="flex items-center">
                <div className="flex-shrink-0 bg-blue-500 rounded-md p-3">
                  <svg
                    className="h-6 w-6 text-white"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
                    />
                  </svg>
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm leading-5 font-medium text-gray-500 truncate">
                      Projects generated
                    </dt>
                    <dd className="flex items-baseline">
                      <div className="text-2xl leading-8 font-semibold text-gray-900">
                        71897
                      </div>
                      <div className="ml-2 flex items-baseline text-sm leading-5 font-semibold text-green-600">
                        <svg
                          className="self-center flex-shrink-0 h-5 w-5 text-green-500"
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path
                            fillRule="evenodd"
                            d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z"
                            clipRule="evenodd"
                          />
                        </svg>
                        <span className="sr-only">Increased by</span>
                        122
                      </div>
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
            <div className="bg-gray-50 px-4 py-4 sm:px-6">
              <div className="text-sm leading-5">
                <a
                  href="#"
                  className="font-medium text-blue-600 hover:text-blue-500 transition ease-in-out duration-150"
                >
                  View all
                </a>
              </div>
            </div>
          </div>
          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="px-4 py-5 sm:p-6">
              <div className="flex items-center">
                <div className="flex-shrink-0 bg-blue-500 rounded-md p-3">
                  <svg
                    className="h-6 w-6 text-white"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M3 19v-8.93a2 2 0 01.89-1.664l7-4.666a2 2 0 012.22 0l7 4.666A2 2 0 0121 10.07V19M3 19a2 2 0 002 2h14a2 2 0 002-2M3 19l6.75-4.5M21 19l-6.75-4.5M3 10l6.75 4.5M21 10l-6.75 4.5m0 0l-1.14.76a2 2 0 01-2.22 0l-1.14-.76"
                    />
                  </svg>
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm leading-5 font-medium text-gray-500 truncate">
                      Focused projects
                    </dt>
                    <dd className="flex items-baseline">
                      <div className="text-2xl leading-8 font-semibold text-gray-900">
                        50922
                      </div>
                      <div className="ml-2 flex items-baseline text-sm leading-5 font-semibold text-green-600">
                        <svg
                          className="self-center flex-shrink-0 h-5 w-5 text-green-500"
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path
                            fillRule="evenodd"
                            d="M5.293 9.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 7.414V15a1 1 0 11-2 0V7.414L6.707 9.707a1 1 0 01-1.414 0z"
                            clipRule="evenodd"
                          />
                        </svg>
                        <span className="sr-only">Increased by</span>
                        300
                      </div>
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
            <div className="bg-gray-50 px-4 py-4 sm:px-6">
              <div className="text-sm leading-5">
                <a
                  href="#"
                  className="font-medium text-blue-600 hover:text-blue-500 transition ease-in-out duration-150"
                >
                  View all
                </a>
              </div>
            </div>
          </div>
          <div className="bg-white overflow-hidden shadow rounded-lg">
            <div className="px-4 py-5 sm:p-6">
              <div className="flex items-center">
                <div className="flex-shrink-0 bg-blue-500 rounded-md p-3">
                  <svg
                    className="h-6 w-6 text-white"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M15 15l-2 5L9 9l11 4-5 2zm0 0l5 5M7.188 2.239l.777 2.897M5.136 7.965l-2.898-.777M13.95 4.05l-2.122 2.122m-5.657 5.656l-2.12 2.122"
                    />
                  </svg>
                </div>
                <div className="ml-5 w-0 flex-1">
                  <dl>
                    <dt className="text-sm leading-5 font-medium text-gray-500 truncate">
                      Scaffolds
                    </dt>
                    <dd className="flex items-baseline">
                      <div className="text-2xl leading-8 font-semibold text-gray-900">
                        24300
                      </div>
                      <div className="ml-2 flex items-baseline text-sm leading-5 font-semibold text-red-600">
                        <svg
                          className="self-center flex-shrink-0 h-5 w-5 text-red-500"
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path
                            fillRule="evenodd"
                            d="M14.707 10.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 12.586V5a1 1 0 012 0v7.586l2.293-2.293a1 1 0 011.414 0z"
                            clipRule="evenodd"
                          />
                        </svg>
                        <span className="sr-only">Decreased by</span>
                        24
                      </div>
                    </dd>
                  </dl>
                </div>
              </div>
            </div>
            <div className="bg-gray-50 px-4 py-4 sm:px-6">
              <div className="text-sm leading-5">
                <a
                  href="#"
                  className="font-medium text-blue-600 hover:text-blue-500 transition ease-in-out duration-150"
                >
                  View all
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

const Header = () => {
  return (
    <div>
      <div className="flex justify-center mb-16">
        <a href="https://tuist.io">
          <img src="/logo.svg" />
        </a>
      </div>
      <p className="text-base text-center leading-6 text-blue-600 font-semibold tracking-wide uppercase">
        Tuist Stats
      </p>
      <h1 className="mt-2 mb-8 text-3xl text-center leading-8 font-extrabold tracking-tight text-gray-900 sm:text-4xl sm:leading-10">
        Insights about how people use Tuist
      </h1>
      <p className="text-center text-gray-700 leading-8 prose-lg">
        To prioritize the work and make the right decisions, it's important to{' '}
        <b>back our decisions with data</b>. For that reason, we collect
        anonymous data and present it on this website for us and for the users
        of the tool.
      </p>
      <p className="text-center text-yellow-700 leading-8 prose-lg">
        Please note that this website is currently work-in-progress so the data
        presented is fake at the moment.
      </p>
    </div>
  )
}
function HomePage() {
  return (
    <div>
      <Head />
      <div className="relative py-16 bg-white overflow-hidden max-w-screen-lg mx-auto">
        <div className="relative px-4 sm:px-6 lg:px-8">
          <div className="text-lg max-w-prose mx-auto mb-6">
            <Header />
            <Workflows />
            <Projects />
            <Environment />
          </div>
        </div>
      </div>
    </div>
  )
}

export default HomePage
