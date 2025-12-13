import { Toaster } from 'react-hot-toast';
import ProductList from './components/ProductList';
import Notifications from './components/Notifications';
import './App.css'

function App() {
  return (
    <>
      <Toaster position="top-right" />
      <Notifications />
      <h1>GraphQL Gateway Shop</h1>
      <div className="card">
        <p>
          Select a product to purchase. The order will be processed asynchronously by the Back Office worker.
        </p>
      </div>
      <ProductList />
    </>
  )
}

export default App

