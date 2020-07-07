/** @jsx jsx */
import { jsx, Styled } from 'theme-ui'
import { useStaticQuery, graphql } from 'gatsby'
import Layout from '../components/layout'
import Main from '../components/main'
import { GatsbySeo } from 'gatsby-plugin-next-seo'
import SEO from '../components/SEO'
import Stickers from '../../assets/stickers.svg'
import countryList from 'react-select-country-list'
import Select from 'react-select'

const Form = () => {
  const countries = countryList().getData()
  return (
    <form
      netlify
      name="Stickers form"
      method="POST"
      action="/stickers-requested"
    >
      <div>
        <div className="mt-8 border-gray-200 pt-8">
          <div className="mt-6 grid grid-cols-1 row-gap-6 col-gap-4 sm:grid-cols-6">
            <div className="sm:col-span-3">
              <label
                htmlFor="first_name"
                className="block text-sm font-medium leading-5 text-gray-700"
              >
                First name
              </label>
              <div className="mt-1 rounded-md shadow-sm">
                <input
                  id="first_name"
                  name="First name"
                  className="form-input px-2 block w-full transition duration-150 ease-in-out sm:text-sm sm:leading-10"
                />
              </div>
            </div>
            <div className="sm:col-span-3">
              <label
                htmlFor="last_name"
                className="block text-sm font-medium leading-5 text-gray-700"
              >
                Last name
              </label>
              <div className="mt-1 rounded-md shadow-sm">
                <input
                  id="last_name"
                  name="Last name"
                  className="form-input px-2 block w-full transition duration-150 ease-in-out sm:text-sm sm:leading-10"
                />
              </div>
            </div>
            <div className="sm:col-span-3">
              <label
                htmlFor="country"
                className="block text-sm font-medium leading-5 text-gray-700"
              >
                Country / Region
              </label>
              <div className="mt-1 rounded-md shadow-sm">
                <Select
                  id="country"
                  name="Country"
                  options={countries}
                  className="form-select block w-full transition duration-150 ease-in-out sm:text-sm sm:leading-10"
                />
              </div>
            </div>
            <div className="sm:col-span-6">
              <label
                htmlFor="street_address"
                className="block text-sm font-medium leading-5 text-gray-700"
              >
                Street address
              </label>
              <div className="mt-1 rounded-md shadow-sm">
                <input
                  id="street_address"
                  name="Address"
                  className="form-input px-2 block w-full transition duration-150 ease-in-out sm:text-sm sm:leading-10"
                />
              </div>
            </div>
            <div className="sm:col-span-2">
              <label
                htmlFor="city"
                className="block text-sm font-medium leading-5 text-gray-700"
              >
                City
              </label>
              <div className="mt-1 rounded-md shadow-sm">
                <input
                  id="city"
                  name="City"
                  className="form-input px-2 block w-full transition duration-150 ease-in-out sm:text-sm sm:leading-10"
                />
              </div>
            </div>
            <div className="sm:col-span-2">
              <label
                htmlFor="state"
                className="block text-sm font-medium leading-5 text-gray-700"
              >
                State / Province
              </label>
              <div className="mt-1 rounded-md shadow-sm">
                <input
                  id="state"
                  name="State"
                  className="form-input px-2 block w-full transition duration-150 ease-in-out sm:text-sm sm:leading-10"
                />
              </div>
            </div>
            <div className="sm:col-span-2">
              <label
                htmlFor="zip"
                className="block text-sm font-medium leading-5 text-gray-700"
              >
                ZIP / Postal
              </label>
              <div className="mt-1 rounded-md shadow-sm">
                <input
                  id="zip"
                  name="ZIP"
                  className="form-input px-2 block w-full transition duration-150 ease-in-out sm:text-sm sm:leading-10"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
      <div className="mt-8 border-gray-200 pt-5">
        <div className="flex justify-center">
          <span className="ml-3 inline-flex rounded-md shadow-sm">
            <button
              type="submit"
              className="inline-flex justify-center py-2 px-4 border border-transparent text-sm leading-5 font-medium rounded-md text-white bg-blue-600 hover:bg-blue-500 focus:outline-none focus:border-blue-700 focus:shadow-outline-blue active:bg-blue-700 transition duration-150 ease-in-out"
            >
              Send me some!
            </button>
          </span>
        </div>
      </div>
    </form>
  )
}
export default () => {
  return (
    <Layout>
      <SEO title="Stickers" />
      <GatsbySeo
        title="Stickers"
        description={`Wanna get some nice-looking free stickers for your laptop? You can request some from this page.`}
      />
      <Main>
        <Styled.h1>Get stickers</Styled.h1>
        <Styled.p>
          Wanna get some nice-looking stickers for free? You can request some
          using the form below. We send them anywhere in the world!
        </Styled.p>
        <div>
          <Stickers sx={{ height: 200, width: 200, margin: 'auto' }} />
        </div>
        <div>
          <Form />
        </div>
      </Main>
    </Layout>
  )
}
