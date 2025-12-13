import { useQuery, gql } from '@apollo/client';
import OrderButton from './OrderButton';

const GET_PRODUCTS = gql`
  query GetProducts {
    products {
      nodes {
        id
        name
        price
      }
    }
  }
`;

export default function ProductList() {
  const { loading, error, data } = useQuery(GET_PRODUCTS);

  if (loading) return <p>Loading products...</p>;
  if (error) return <p>Error: {error.message}</p>;

  return (
    <div className="grid">
      {data.products.nodes.map((product: any) => (
        <div key={product.id} className="card">
          <h3>{product.name}</h3>
          <p>${product.price}</p>
          <OrderButton productId={product.id} />
        </div>
      ))}
    </div>
  );
}
